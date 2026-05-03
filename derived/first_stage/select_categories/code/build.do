set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    select_good_categories, embed("tfidf")
end

program select_good_categories
    syntax, embed(string)
    import delimited ../external/samp/combined_full_report_gatekeeper_tfidf_expert_`embed', clear
    cap rename v1 category
    drop if inlist(category, "macro avg", "weighted avg", "Non-Lab", "accuracy")

*===============================================================================
* TREATED PRODUCT MARKET CLASSIFICATION
* Thermo Fisher / Life Technologies Merger
*
* Classification rule: treated ONLY if the product market is mentioned in
* antitrust documents (EU COMP/M.6944, FTC Complaint, China MOFCOM) as an
* area of overlap. Tier 3 = bundled/extension robustness check (categories
* not directly named in antitrust documents but plausibly co-purchased
* with documented overlap markets).
*
* Tier 1 (Definitely treated; serious-doubts → divestiture):           31
* Tier 2 (EU confirmed overlap, no serious doubts):                   152
* Tier 3 (Bundling/extension robustness):                              66
* Control:                                                           ~770
*-------------------------------------------------------------------------------
* CHANGELOG vs. previous version (Apr 2026 audit against EU/FTC text):
*   - synthetic crrna           Tier 1   → Control  (not in any ruling)
*   - dntps                     Tier 2   → Control  (EU para 126: standard reagent)
*   - taq buffers               Tier 2   → Control  (EU para 126: standard reagent)
*   - synthetic shrna           Tier 1   → Tier 2   (EU para 88: no serious doubts)
*   - magnetic bead-based mrna selection kit
*                               Tier 1   → Tier 2   (Level B NA purification)
*   - PBS / DPBS / HBSS         Tier 3   → Tier 1   (EU para 27: process liquids,
*                                                    divested with HyClone)
*   - 14 magnetic affinity resins        Tier 1 → Tier 3
*   - immunomagnetic cell sep beads/columns,
*     magnetic beads - other,
*     magnetic cell separation kits,
*     magnetic ip kit           Tier 1   → Tier 3
*       Reason: EU magnetic-bead divestiture was Thermo's Sera-Mag/SpeedBeads
*       (OEM polymer-based beads, ~10-20% share), NOT Life's Dynabeads
*       (~50-60% share). EU explicitly distinguished OEM from end-user supply
*       (paras 219-227); academic data captures end-user products.
*   - 7 Western blot accessories Tier 2  → Tier 3
*       (gel blotting papers, blockers, enhancers, pens, rollers,
*       stripping buffers, transfer buffers — EU para 309 narrows WB
*       overlap to transfer boxes + membranes + chemiluminescent substrates)
*   - horse serum                Control → Tier 1   (EU para 44 fn: equine sera
*                                                    in HyClone divestiture)
*   - nz bovine calf serum       Control → Tier 1   (HyClone divestiture)
*===============================================================================

gen tier1 = 0
gen tier2 = 0
gen tier3 = 0

*-------------------------------------------------------------------------------
* TIER 1: DEFINITELY TREATED — divestitures required by serious-doubts finding
*   1. Cell culture media (HyClone divestiture, EU IV.C.1)
*   2. Cell culture sera (HyClone divestiture, EU IV.C.2)
*   3. Process liquids (HyClone divestiture, EU para 27)
*   4. siRNA / gene silencing (Dharmacon divestiture, EU IV.D.1)
*-------------------------------------------------------------------------------

* --- Cell culture media (HyClone, all forms) ---
replace tier1 = 1 if category == "basal medium eagle"
replace tier1 = 1 if category == "dmem"
replace tier1 = 1 if category == "dmem/f-12"
replace tier1 = 1 if category == "dry basal media, not chemically defined"
replace tier1 = 1 if category == "hams f12"
replace tier1 = 1 if category == "imdm"
replace tier1 = 1 if category == "insect cell media"
replace tier1 = 1 if category == "leibovitz l15 media"
replace tier1 = 1 if category == "mccoys 5a"
replace tier1 = 1 if category == "mem"
replace tier1 = 1 if category == "neurobasal media"
replace tier1 = 1 if category == "optimem"
replace tier1 = 1 if category == "rpmi"
replace tier1 = 1 if category == "specialty cell culture media"
replace tier1 = 1 if category == "stem cell media"

* --- Cell culture sera (HyClone, all animal types in divestiture) ---
replace tier1 = 1 if category == "australian fbs"
replace tier1 = 1 if category == "bovine adult serum"
replace tier1 = 1 if category == "bovine calf serum"
replace tier1 = 1 if category == "canadian fbs"
replace tier1 = 1 if category == "horse serum"
replace tier1 = 1 if category == "new zealand fbs"
replace tier1 = 1 if category == "nz bovine calf serum"
replace tier1 = 1 if category == "us fbs"

* --- Process liquids (EU para 27 — explicitly within cell culture market;
*     divested as part of HyClone "all liquid and dry powder media (including
*     process liquids) product lines", EU Exhibit A) ---
replace tier1 = 1 if category == "dulbecco's phosphate-buffered saline (dpbs) buffer"
replace tier1 = 1 if category == "hanks' balanced salt solution (hbss) buffer"
replace tier1 = 1 if category == "phosphate-buffered saline (pbs) buffer"

* --- Gene silencing (Dharmacon Lafayette divestiture; EU paras 89-105) ---
*     siRNA and miRNA were the EU "serious doubts" categories.
*     shRNA was geographically bundled into the divestiture but EU para 88
*     found "no serious doubts" → see Tier 2 below.
*     crRNA is NOT in either ruling → control.
replace tier1 = 1 if category == "gene-specific rnai reagents"
replace tier1 = 1 if category == "sirna buffers"
replace tier1 = 1 if category == "sirna transfection medium"
replace tier1 = 1 if category == "sirna transfection reagents"
replace tier1 = 1 if category == "synthetic sirna"

count if tier1 == 1

*-------------------------------------------------------------------------------
* TIER 2: EU CONFIRMED OVERLAP, CLEARED (no serious doubts)
*   Mix of paragraph 11 detailed-analysis areas (transfection, HF/hot-start
*   polymerases, RT enzymes, MW standards) and paragraph 12 quick-clearance
*   areas (Taq, PCR/qPCR/RT-PCR kits, cloning, SDS-PAGE products, Western
*   blot transfer-boxes/membranes/chemilum substrates, protein modification,
*   reactive dyes, shRNA, NA amplification instruments).
*-------------------------------------------------------------------------------

* --- shRNA (EU para 12(i), 88: no serious doubts; reclassified from Tier 1) ---
replace tier2 = 1 if category == "synthetic shrna"

* --- Transfection / delivery systems (EU IV.D.2, para 11(iii)) ---
replace tier2 = 1 if category == "transfection reagents"
replace tier2 = 1 if category == "transfection reagents - cellfectin (insect cell)"
replace tier2 = 1 if category == "transfection reagents - electroporation kits"
replace tier2 = 1 if category == "transfection reagents - electroporation reagent"
replace tier2 = 1 if category == "transfection reagents - in vivo delivery reagents"
replace tier2 = 1 if category == "transfection reagents - lentiviral packaging kits"
replace tier2 = 1 if category == "transfection reagents - other"
replace tier2 = 1 if category == "transfection reagents - polybrene (viral transduction)"
replace tier2 = 1 if category == "transfection reagents - protein transfection reagents"

* --- NA amplification: differentiated enzymes (EU IV.D.3, para 11(iv)) ---
*     High-fidelity, hot-start, RT enzymes — detailed analysis with combined
*     shares 40-50%; cleared due to de minimis increment, IP fragmentation,
*     and competitor capacity.
replace tier2 = 1 if category == "high-fidelity dna polymerase"
replace tier2 = 1 if category == "high-fidelity hot start dna polymerase"
replace tier2 = 1 if category == "high-fidelity hot start pcr systems"
replace tier2 = 1 if category == "high-fidelity pcr systems"
replace tier2 = 1 if category == "hot start pcr systems"
replace tier2 = 1 if category == "hot start taq polymerase"
replace tier2 = 1 if category == "reverse transcriptase"

* --- NA amplification: Taq + PCR/qPCR/RT-PCR kits (EU para 12(iii), (iv)) ---
*     EU para 126 EXCLUDES standard reagents (dNTPs, buffers); those are
*     control. Differentiated kits and Taq polymerase are Tier 2.
replace tier2 = 1 if category == "capped mrna synthesis kits"
replace tier2 = 1 if category == "custom-designed qpcr assays"
replace tier2 = 1 if category == "direct pcr lysis reagents"
replace tier2 = 1 if category == "dye-based qpcr systems"
replace tier2 = 1 if category == "dye-based rt-qpcr systems"
replace tier2 = 1 if category == "in vitro transcription kit"
replace tier2 = 1 if category == "long template pcr systems"
replace tier2 = 1 if category == "microrna reverse transcription kit"
replace tier2 = 1 if category == "pcr barcoding expansion"
replace tier2 = 1 if category == "pcr systems"
replace tier2 = 1 if category == "pre amplification kits"
replace tier2 = 1 if category == "pre-designed qpcr assays"
replace tier2 = 1 if category == "probe-based qpcr systems"
replace tier2 = 1 if category == "probe-based rt-qpcr systems"
replace tier2 = 1 if category == "qpcr beads"
replace tier2 = 1 if category == "qrt-pcr titration kit"
replace tier2 = 1 if category == "rt-pcr systems"
replace tier2 = 1 if category == "taq polymerases"
replace tier2 = 1 if category == "tissue pcr systems"

* --- First-strand cDNA / RT systems (paras 11(iv) area) ---
replace tier2 = 1 if category == "first-strand cdna synthesis systems"

* --- NA purification: column-based kits, RNA extraction, mag-bead instruments
*     (EU IV.D.4, para 11(v)) ---
replace tier2 = 1 if category == "column-based dna and rna extraction kits"
replace tier2 = 1 if category == "column-based dna genomic purification kits"
replace tier2 = 1 if category == "column-based dna plasmid gigaprep"
replace tier2 = 1 if category == "column-based dna plasmid maxiprep"
replace tier2 = 1 if category == "column-based dna plasmid megaprep"
replace tier2 = 1 if category == "column-based dna plasmid midiprep"
replace tier2 = 1 if category == "column-based dna plasmid miniprep"
replace tier2 = 1 if category == "column-based dna purification kits"
replace tier2 = 1 if category == "column-based gel dna extraction kits"
replace tier2 = 1 if category == "column-based gel rna extraction kits"
replace tier2 = 1 if category == "column-based microbial dna purification kits"
replace tier2 = 1 if category == "column-based pcr and gel purification kit"
replace tier2 = 1 if category == "column-based pcr purification kits"
replace tier2 = 1 if category == "column-based pcr purification reagent"
replace tier2 = 1 if category == "column-based plant dna purification kits"
replace tier2 = 1 if category == "column-based plant rna purification kits"
replace tier2 = 1 if category == "column-based protein purification kit"
replace tier2 = 1 if category == "column-based rna purification kits"
replace tier2 = 1 if category == "column-based yeast dna purification kits"
replace tier2 = 1 if category == "liquid-based dna plasmid purification kit"
replace tier2 = 1 if category == "magnetic-bead based purification kit"
replace tier2 = 1 if category == "magnetic bacterial rna purification kit"
replace tier2 = 1 if category == "magnetic bead-based mrna selection kit"  // moved from Tier 1
replace tier2 = 1 if category == "rna extraction reagents"
replace tier2 = 1 if category == "rna stabilization reagent"
replace tier2 = 1 if category == "silica bead based gel purification kit"
replace tier2 = 1 if category == "spin columns"

* --- NA purification: molecular weight standards / DNA & RNA & protein ladders
*     (EU IV.D.4, para 11(v)) ---
replace tier2 = 1 if category == "pre-stained dna ladders"
replace tier2 = 1 if category == "pre-stained protein molecular-weight ladder"
replace tier2 = 1 if category == "pre-stained rna ladders"
replace tier2 = 1 if category == "unstained dna ladders"
replace tier2 = 1 if category == "unstained protein molecular-weight ladder"
replace tier2 = 1 if category == "unstained rna ladders"

* --- Cloning enzymes + kits (EU IV.D.5, para 12(vi)) ---
replace tier2 = 1 if category == "bacterial transformation reagents"
replace tier2 = 1 if category == "blunt-end cloning kits"
replace tier2 = 1 if category == "chemically competent cells"
replace tier2 = 1 if category == "directional topo cloning kits"
replace tier2 = 1 if category == "dnase i"
replace tier2 = 1 if category == "electrocompetent cells"
replace tier2 = 1 if category == "expression plasmids"
replace tier2 = 1 if category == "gateway cloning kits"
replace tier2 = 1 if category == "modified nucleotides"
replace tier2 = 1 if category == "nuclease enzymes"
replace tier2 = 1 if category == "nucleic acid quantitation"
replace tier2 = 1 if category == "plasmid vectors"
replace tier2 = 1 if category == "radiolabeled nucleotides"
replace tier2 = 1 if category == "rapid dna ligation kits"
replace tier2 = 1 if category == "restriction enzyme buffers"
replace tier2 = 1 if category == "restriction enzymes"
replace tier2 = 1 if category == "rna polymerases"
replace tier2 = 1 if category == "rnase"
replace tier2 = 1 if category == "rnase inhibitors"
replace tier2 = 1 if category == "seamless cloning kits"
replace tier2 = 1 if category == "site-directed mutagenesis systems"
replace tier2 = 1 if category == "ta cloning kits"
replace tier2 = 1 if category == "taq dna ligases"
replace tier2 = 1 if category == "topo ta cloning kits"
replace tier2 = 1 if category == "zero blunt topo cloning kits"

* --- Nucleic acid modifying enzymes (cloning area, EU para 12(vi)) ---
replace tier2 = 1 if category == "nucleic acid modifying enzymes - alkaline phosphatases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - creatine kinase (non-nucleic acid enzyme)"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - dna fragmentases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - dna methylases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - end repair enzymes"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - endonucleases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - exonucleases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - klenow fragment"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - other"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - other dna polymerases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - other nucleases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - poly(a) polymerases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - pyrophosphatases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - recombinases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - single-stranded dna binding proteins"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 dna ligase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 dna ligase buffer"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 dna polymerase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 polynucleotide kinase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 polynucleotide kinase buffer"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 rna ligase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 rna ligase buffer"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t7 dna ligase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - taq dna ligase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - terminal transferase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - topoisomerases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - transposases"

* --- SDS-PAGE products (EU IV.G.1, para 12(vii) — pre-cast gels, gel stains,
*     gel boxes, MW standards already above) ---
replace tier2 = 1 if category == "acrylamide/bis solution"
replace tier2 = 1 if category == "horizontal electrophoresis systems"
replace tier2 = 1 if category == "phosphoprotein electrophoresis reagents"
replace tier2 = 1 if category == "polyacrylamide gels casting kit"
replace tier2 = 1 if category == "pre-cast bis-tris gels"
replace tier2 = 1 if category == "pre-cast tbe gels"
replace tier2 = 1 if category == "pre-cast tris-acetate gels"
replace tier2 = 1 if category == "pre-cast tris-glycine gels"
replace tier2 = 1 if category == "pre-cast tris-hcl gels"
replace tier2 = 1 if category == "pre-cast tris-tricine gels"
replace tier2 = 1 if category == "protein gel stains"
replace tier2 = 1 if category == "vertical electrophoresis systems"

* --- Western blotting: TRANSFER BOXES, MEMBRANES, CHEMILUM SUBSTRATES ONLY
*     (EU IV.G.2, para 309 narrowly defines the overlap to these three) ---
replace tier2 = 1 if category == "chemiluminescent substrates"
replace tier2 = 1 if category == "chemiluminescent western blot detection"
replace tier2 = 1 if category == "nitrocellulose blotting membranes"
replace tier2 = 1 if category == "precut nitrocellulose transfer blotting packs"
replace tier2 = 1 if category == "precut pvdf transfer blotting packs"
replace tier2 = 1 if category == "pvdf blotting membranes"
replace tier2 = 1 if category == "western blot boxes"

* --- Protein modification (EU IV.G.3, para 12(ix)) ---
replace tier2 = 1 if category == "antibody labeling kits"
replace tier2 = 1 if category == "bioconjugation reagents"
replace tier2 = 1 if category == "crosslinking reagents"
replace tier2 = 1 if category == "protein and antibody labeling kits"
replace tier2 = 1 if category == "protein modifying enzymes"
replace tier2 = 1 if category == "protein quantitation assay kits"

* --- Reactive dyes + bioconjugation fluorophores (EU IV.G.4, para 12(x)) ---
replace tier2 = 1 if category == "fluorophore - bioconjugate dyes"
replace tier2 = 1 if category == "fluorophore - general"
replace tier2 = 1 if category == "fluorophore - nucleic acid stain"
replace tier2 = 1 if category == "nucleic acid gel stains"
replace tier2 = 1 if category == "quantum dots"
replace tier2 = 1 if category == "streptavidin conjugates"

count if tier2 == 1

*-------------------------------------------------------------------------------
* TIER 3: BUNDLED / EXTENSION ROBUSTNESS
*   These categories are NOT directly named as overlap markets in the
*   antitrust documents. They are included as a robustness check on the
*   hypothesis that price effects in documented overlap markets spill over
*   to commonly co-purchased products. NOTE: This tier intentionally
*   relaxes the "antitrust-document-named" rule; results using
*   `treated` (= T1+T2+T3) should be reported as such.
*-------------------------------------------------------------------------------

* --- Cell culture supplements (bundled with HyClone media purchases) ---
replace tier3 = 1 if category == "cell culture nutritional supplements - amino acids"
replace tier3 = 1 if category == "cell culture nutritional supplements - b27"
replace tier3 = 1 if category == "cell culture nutritional supplements - casamino acids"
replace tier3 = 1 if category == "cell culture nutritional supplements - glucose"
replace tier3 = 1 if category == "cell culture nutritional supplements - insulin"
replace tier3 = 1 if category == "cell culture nutritional supplements - its-g"
replace tier3 = 1 if category == "cell culture nutritional supplements - l-glutamine"
replace tier3 = 1 if category == "cell culture nutritional supplements - lif"
replace tier3 = 1 if category == "cell culture nutritional supplements - other"
replace tier3 = 1 if category == "cell culture nutritional supplements - peptone"
replace tier3 = 1 if category == "cell culture nutritional supplements - sodium pyruvate"
replace tier3 = 1 if category == "cell culture nutritional supplements - sugars"
replace tier3 = 1 if category == "cell culture nutritional supplements - tryptone"
replace tier3 = 1 if category == "cell culture nutritional supplements - vitamins"
replace tier3 = 1 if category == "cell culture nutritional supplements - yeast"
replace tier3 = 1 if category == "cell culture dissociation reagents"
replace tier3 = 1 if category == "growth medium supplement"

* --- End-user magnetic beads (NOT in EU divestiture; Sera-Mag/SpeedBeads
*     was Thermo's OEM business — Life's Dynabeads end-user products were
*     analyzed as a separate market with no concerns, EU paras 219-227.
*     Moved here from Tier 1 to test bundling-style spillover, not direct
*     antitrust effect.) ---
replace tier3 = 1 if category == "affinity resins - activated coupling matrices (magnetic)"
replace tier3 = 1 if category == "affinity resins - anti-ig secondary (magnetic)"
replace tier3 = 1 if category == "affinity resins - biotin/avidin (magnetic)"
replace tier3 = 1 if category == "affinity resins - epitope tags (flag/ha/myc/v5) (magnetic)"
replace tier3 = 1 if category == "affinity resins - glycoprotein (lectin-immobilized) (magnetic)"
replace tier3 = 1 if category == "affinity resins - gst-tag (magnetic)"
replace tier3 = 1 if category == "affinity resins - his-tag (imac) (magnetic)"
replace tier3 = 1 if category == "affinity resins - mbp-tag (magnetic)"
replace tier3 = 1 if category == "affinity resins - other (magnetic)"
replace tier3 = 1 if category == "affinity resins - protein a (magnetic)"
replace tier3 = 1 if category == "affinity resins - protein a/g (magnetic)"
replace tier3 = 1 if category == "affinity resins - protein g (magnetic)"
replace tier3 = 1 if category == "affinity resins - strep-tag (magnetic)"
replace tier3 = 1 if category == "affinity resins - streptavidin/avidin (magnetic)"
replace tier3 = 1 if category == "immunomagnetic cell separation beads"
replace tier3 = 1 if category == "immunomagnetic cell separation columns"
replace tier3 = 1 if category == "magnetic beads - other"
replace tier3 = 1 if category == "magnetic cell separation kits"
replace tier3 = 1 if category == "magnetic ip kit"

* --- Electrophoresis sample/running buffers (bundled with Tier 2 SDS-PAGE) ---
replace tier3 = 1 if category == "laemmli sample buffer"
replace tier3 = 1 if category == "lds sample buffer"
replace tier3 = 1 if category == "ligation reaction buffer"
replace tier3 = 1 if category == "mes-sds buffer"
replace tier3 = 1 if category == "mops-sds buffer"
replace tier3 = 1 if category == "native page running buffers"
replace tier3 = 1 if category == "native-page sample buffer"
replace tier3 = 1 if category == "reaction buffers"
replace tier3 = 1 if category == "reducing agents - bme"
replace tier3 = 1 if category == "tbe buffer"
replace tier3 = 1 if category == "tris-aceate-sds running buffer"
replace tier3 = 1 if category == "tris-acetate-edta (tae) buffer"
replace tier3 = 1 if category == "tris-glycine buffer"
replace tier3 = 1 if category == "tris-glycine-sds (tgs) buffer"
replace tier3 = 1 if category == "tris-tricine-sds buffer"

* --- Western blot accessories (NOT in EU para 309 narrow overlap definition;
*     bundled with Tier 2 transfer boxes / membranes / chemilum substrates) ---
replace tier3 = 1 if category == "gel blotting papers"
replace tier3 = 1 if category == "western blot blockers"
replace tier3 = 1 if category == "western blot enhancers"
replace tier3 = 1 if category == "western blot pen"
replace tier3 = 1 if category == "western blot rollers"
replace tier3 = 1 if category == "western blot stripping buffers"
replace tier3 = 1 if category == "western blot transfer buffers"

* --- Fluorophore subtypes (Molecular Probes line; bundling with reactive dyes,
*     not directly in EU para 12(x) overlap) ---
replace tier3 = 1 if category == "fluorophore - calcium indicators"
replace tier3 = 1 if category == "fluorophore - cell tracer"
replace tier3 = 1 if category == "fluorophore - glutathione indicator"
replace tier3 = 1 if category == "fluorophore - lysosome indicators"
replace tier3 = 1 if category == "fluorophore - protein hydrophobicity"
replace tier3 = 1 if category == "fluorophore - ros indicators"
replace tier3 = 1 if category == "fluorophore - voltage indicators"
replace tier3 = 1 if category == "viability stains"


*-------------------------------------------------------------------------------
* DEFENSIVE CHECKS — categories explicitly EXCLUDED from treatment
*-------------------------------------------------------------------------------
* The following are NOT treated, by EU/FTC text:
*   - synthetic crrna (CRISPR not in any ruling)
*   - dntps (EU para 126: standard reagent, "not affected")
*   - taq buffers (EU para 126: standard reagent, "not affected")
* Verify they are NOT classified as treated:
foreach c in "synthetic crrna" "dntps" "taq buffers" {
    count if category == "`c'" & (tier1 == 1 | tier2 == 1 | tier3 == 1)
    assert r(N) == 0
}

*-------------------------------------------------------------------------------
* MASTER TREATMENT VARIABLES
*-------------------------------------------------------------------------------
gen treated_strict = (tier1 == 1)
gen treated_1and2  = (tier1 == 1 | tier2 == 1)
gen treated        = (tier1 == 1 | tier2 == 1 | tier3 == 1)

label var tier1          "Tier 1: divestiture / serious-doubts (cell culture, sera, siRNA)"
label var tier2          "Tier 2: EU confirmed overlap, no serious doubts"
label var tier3          "Tier 3: bundled / extension robustness"
label var treated_strict "Treated (Tier 1 only)"
label var treated_1and2  "Treated (Tier 1 + Tier 2)"
label var treated        "Treated (Tier 1 + Tier 2 + Tier 3)"

tab tier1
tab tier2
tab tier3
tab treated_strict
tab treated_1and2
tab treated

    gen keep = (support >= 20 & precision >= 0.8 & recall >= 0.8) //| (inrange(support, 10, 25) & precision >= 0.9 & recall >=0.90)
    save ../output/categories_`embed', replace
end
main
