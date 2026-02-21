# inspect_pipeline.py
"""
Interactive diagnostic tool: enter product descriptions and see exactly how
the full classification pipeline handles each one.

Usage:
    python code/inspect_pipeline.py --gatekeeper tfidf --expert non_parametric_tfidf
    python code/inspect_pipeline.py --gatekeeper bert  --expert non_parametric_bert

You can also pass descriptions directly via --items:
    python code/inspect_pipeline.py --gatekeeper tfidf --expert non_parametric_tfidf \
        --items "corning 96 well plate" "kimwipe delicate task wiper"
"""
import argparse
import os
import joblib
import numpy as np

import config
from classifier import (
    HybridClassifier,
    has_match,
    load_keywords_and_build_automaton,
    extract_market_keywords_and_build_automaton,
)
from rule_based_categorizer import RuleBasedCategorizer
from categorize_items import TfidfItemCategorizer, EmbeddingItemCategorizer


def load_models(gatekeeper_name: str, expert_choice: str):
    """Load gatekeeper, expert, and rule models once."""
    gatekeeper = joblib.load(
        os.path.join(config.OUTPUT_DIR, f"hybrid_classifier_{gatekeeper_name}.joblib")
    )

    model_type, embedding_type = expert_choice.rsplit("_", 1)
    if embedding_type == "tfidf":
        expert = TfidfItemCategorizer()
    elif embedding_type == "bert":
        expert = EmbeddingItemCategorizer("bert", "all-MiniLM-L6-v2")
    else:
        raise ValueError(f"Unsupported embedding type: {embedding_type}")

    rule_categorizer = RuleBasedCategorizer(config.MARKET_RULES_YAML)
    return gatekeeper, expert, rule_categorizer


def trace_item(desc: str, gatekeeper: HybridClassifier, expert, rule_cat: RuleBasedCategorizer):
    """Run a single description through the full pipeline and return a trace dict."""
    trace = {"input": desc}

    # ---- 0. Text cleaning (what the ML model sees) ----
    trace["cleaned_for_model"] = config.clean_for_model(desc)

    # ---- 1. Keyword gates (Aho-Corasick, operates on RAW text) ----
    anti_seed = has_match(desc, gatekeeper.anti_seed_automaton)
    seed = has_match(desc, gatekeeper.seed_automaton)
    market_kw = has_match(desc, gatekeeper.market_rule_automaton)
    strong = has_match(desc, gatekeeper.strong_lab_automaton)

    trace["anti_seed_match"] = anti_seed
    trace["seed_match"] = seed
    trace["market_keyword_match"] = market_kw
    trace["strong_lab_signal"] = strong

    # ---- 2. ML probability ----
    cleaned = config.clean_for_model(desc)
    if gatekeeper.is_bert:
        vec = gatekeeper.vectorizer.encode([cleaned], show_progress_bar=False)
    else:
        vec = gatekeeper.vectorizer.transform([cleaned])
    ml_prob = gatekeeper.ml_model.predict_proba(vec)[:, 1][0]
    trace["ml_prob_lab"] = round(float(ml_prob), 4)

    # ---- 3. Gatekeeper decision ----
    if anti_seed:
        gate_label = 0
        gate_reason = "Anti-seed keyword -> Non-Lab"
    elif market_kw or seed:
        if strong:
            gate_label = 1
            gate_reason = "Keyword + strong signal -> Lab (ML override blocked)"
        elif ml_prob < config.KEYWORD_OVERRIDE_THRESHOLD:
            gate_label = 0
            gate_reason = (
                f"Keyword match BUT ML prob {ml_prob:.3f} < "
                f"override threshold {config.KEYWORD_OVERRIDE_THRESHOLD} -> Non-Lab"
            )
        else:
            gate_label = 1
            gate_reason = "Keyword match, ML agrees -> Lab"
    else:
        if ml_prob >= config.PREDICTION_THRESHOLD:
            gate_label = 1
            gate_reason = f"No keywords, ML prob {ml_prob:.3f} >= {config.PREDICTION_THRESHOLD} -> Lab"
        else:
            gate_label = 0
            gate_reason = f"No keywords, ML prob {ml_prob:.3f} < {config.PREDICTION_THRESHOLD} -> Non-Lab"

    trace["gatekeeper_label"] = gate_label
    trace["gatekeeper_reason"] = gate_reason

    # ---- 4. Expert model (only if gatekeeper says Lab) ----
    if gate_label == 1:
        category, score = expert.get_item_category(desc)
        trace["expert_category"] = category
        trace["expert_score"] = round(float(score), 4)
    else:
        trace["expert_category"] = None
        trace["expert_score"] = None

    # ---- 5. Veto rules ----
    if trace["expert_category"] and trace["expert_category"] not in ("unclassified", "No Description", "Prediction Error"):
        validated = rule_cat.validate_prediction(trace["expert_category"], desc)
        trace["veto_result"] = validated  # None means vetoed
        trace["was_vetoed"] = validated is None
    else:
        trace["veto_result"] = trace["expert_category"]
        trace["was_vetoed"] = False

    # ---- 6. Market override rules ----
    market_override = rule_cat.get_market_override(desc)
    trace["market_override"] = market_override

    # ---- 7. Final prediction ----
    if gate_label == 0:
        final = "Non-Lab"
        source = "Gatekeeper"
    elif market_override:
        final = market_override
        source = "Market Override"
    elif trace["was_vetoed"]:
        final = "unclassified"
        source = "Vetoed"
    elif trace["veto_result"]:
        final = trace["veto_result"]
        source = "Expert Model"
    else:
        final = "unclassified"
        source = "Expert (unclassified)"

    trace["final_prediction"] = final
    trace["prediction_source"] = source

    return trace


def print_trace(trace: dict):
    """Pretty-print one trace."""
    print("\n" + "=" * 70)
    print(f"  INPUT:  {trace['input']}")
    print(f"  CLEANED: {trace['cleaned_for_model']}")
    print("-" * 70)
    print(f"  Anti-seed match:     {trace['anti_seed_match']}")
    print(f"  Seed match:          {trace['seed_match']}")
    print(f"  Market keyword:      {trace['market_keyword_match']}")
    print(f"  Strong lab signal:   {trace['strong_lab_signal']}")
    print(f"  ML prob (lab):       {trace['ml_prob_lab']}")
    print(f"  Gatekeeper:          {trace['gatekeeper_reason']}")
    print("-" * 70)
    if trace['expert_category']:
        print(f"  Expert prediction:   {trace['expert_category']}  (score: {trace['expert_score']})")
        if trace['was_vetoed']:
            print(f"  Veto:                VETOED (required keyword missing)")
        else:
            print(f"  Veto:                Passed")
    else:
        print(f"  Expert prediction:   (skipped — gatekeeper said Non-Lab)")
    if trace['market_override']:
        print(f"  Market override:     {trace['market_override']}")
    print("-" * 70)
    print(f"  >>> FINAL: {trace['final_prediction']}  (via {trace['prediction_source']})")
    print("=" * 70)


def interactive_mode(gatekeeper, expert, rule_cat):
    """REPL loop for entering descriptions."""
    print("\nEnter product descriptions (one per line). Type 'quit' or 'q' to exit.\n")
    while True:
        try:
            desc = input("Description> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nExiting.")
            break
        if not desc or desc.lower() in ("quit", "q", "exit"):
            break
        trace = trace_item(desc, gatekeeper, expert, rule_cat)
        print_trace(trace)


def main():
    parser = argparse.ArgumentParser(description="Inspect how the pipeline classifies product descriptions.")
    parser.add_argument("--gatekeeper", type=str, required=True, choices=["tfidf", "bert"])
    parser.add_argument("--expert", type=str, required=True,
                        choices=["non_parametric_tfidf", "non_parametric_bert"])
    parser.add_argument("--items", nargs="*", default=None,
                        help="Descriptions to classify. If omitted, enters interactive mode.")
    args = parser.parse_args()

    print("Loading models...")
    gatekeeper, expert, rule_cat = load_models(args.gatekeeper, args.expert)
    print("Models loaded.\n")

    if args.items:
        for desc in args.items:
            trace = trace_item(desc, gatekeeper, expert, rule_cat)
            print_trace(trace)
    else:
        interactive_mode(gatekeeper, expert, rule_cat)


if __name__ == "__main__":
    main()
