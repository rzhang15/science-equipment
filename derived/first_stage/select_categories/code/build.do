set more off
clear all
capture log close
program drop _all
set scheme modern
preliminaries
version 17

program main
    select_good_categories, embed("tfidf") tier3treated  // version A: all3
    select_good_categories, embed("tfidf")               // version B (main): t12
end

* flag <var> "<cat>" ["<cat>" ...]: set <var>=1; a string matching nothing is a
* silent no-op bug, so count matches and fail the build at the end if any are 0
program flag
    gettoken var 0 : 0
    foreach c of local 0 {
        quietly count if category == `"`c'"'
        if r(N) == 0 {
            di as error `"NO MATCH (`var'): `c'"'
            global flag_nomatch = $flag_nomatch + 1
        }
        quietly replace `var' = 1 if category == `"`c'"'
    }
end

program select_good_categories
    syntax, embed(string) [tier3treated]
    import delimited ../external/samp/combined_full_report_gatekeeper_tfidf_expert_`embed', clear
    cap rename v1 category
    drop if inlist(category, "macro avg", "weighted avg", "Non-Lab", "accuracy")

*===============================================================================
* TREATED PRODUCT MARKET CLASSIFICATION (STRICT AUDIT)
* Thermo Fisher / Life Technologies Merger
*
* Strict rule: a category is treated only when the antitrust document text
* directly supports the placement.
*   - Tier 1: subject of an EU "serious doubts" finding (EU paras 41, 69, 98,
*             105, 278) OR explicitly named in the FTC Dharmacon Gene Modulation
*             Products definition (FTC Order def. U) for siRNA/miRNA-specific items.
*   - Tier 2: named in EU para 11 (detailed analysis, no doubts) or para 12
*             (mentioned overlap, summary clearance) or otherwise identified
*             as an overlap in the body text of section IV (e.g., footnote 44
*             for non-FBS sera).
*   - Tier 3: bundling/extension robustness (NOT directly antitrust-document-
*             named; co-purchased with Tier 1/Tier 2 products).
*===============================================================================

gen tier1 = 0
gen tier2 = 0
gen tier3 = 0
global flag_nomatch = 0

*-------------------------------------------------------------------------------
* TIER 1: SERIOUS DOUBTS FINDING IN EU OR FTC GENE MODULATION DIVESTITURE
*-------------------------------------------------------------------------------

* --- Cell culture media (EU para 41 serious doubts; FTC HyClone divested) ---
flag tier1 "basal medium eagle"
flag tier1 "dmem"
flag tier1 "dmem/f-12"
flag tier1 "dry basal media, not chemically defined"
flag tier1 "hams f12"
flag tier1 "imdm"
flag tier1 "insect cell media"
flag tier1 "leibovitz l15 media"
flag tier1 "mccoys 5a"
flag tier1 "mem"
flag tier1 "neurobasal media"
flag tier1 "optimem"
flag tier1 "rpmi"
flag tier1 "specialty cell culture media"
flag tier1 "stem cell media"

* --- FBS (EU para 69 serious doubts; FTC HyClone divested) ---
*     EU para 58: "main area of overlap is the supply of FBS"
*     Non-FBS sera (calf, adult bovine, equine) -> Tier 2 (footnote 44)
flag tier1 "australian fbs"
flag tier1 "canadian fbs"  // Table 8
flag tier1 "new zealand fbs"
flag tier1 "us fbs"
flag tier1 "bovine adult serum"
flag tier1 "bovine calf serum"
flag tier1 "nz bovine calf serum"
flag tier1 "horse serum"

* --- siRNA (EU para 98 serious doubts; FTC Dharmacon Gene Modulation
*     Products def. U includes "small/short interfering RNA (siRNA)") ---
flag tier1 "synthetic sirna"

* --- miRNA: no exact "synthetic mirna" category in current data; FTC def. U
*     includes microRNA. (gene-specific rnai reagents is ambiguous -> Tier 2)

count if tier1 == 1

*-------------------------------------------------------------------------------
* TIER 2: NAMED OVERLAP, NO SERIOUS DOUBTS
*-------------------------------------------------------------------------------
flag tier2 "sirna buffers"  // para-126 standard reagent
flag tier2 "sirna transfection medium"
flag tier2 "sirna transfection reagents"

* --- shRNA (EU para 88: no serious doubts; bundled in Dharmacon divestiture) ---
flag tier2 "synthetic shrna"

* --- Non-FBS sera (footnote 44: overlap markets covered by FBS commitment,
*     "not further considered" by EU) ---
flag tier2 "goat serum"
flag tier2 "donkey serum"
flag tier2 "mouse serum"
flag tier2 "rat serum"
flag tier2 "rabbit serum"
flag tier2 "sheep serum"
* --- Process liquids (EU para 27: separate product market; FTC HyClone
*     divestiture covers them but EU did not analyze for serious doubts) ---
flag tier2 "phosphate-buffered saline (pbs) buffer"
flag tier2 "tris-edta (te) buffer"  // para-126 standard reagent
flag tier2 "dulbecco's phosphate-buffered saline (dpbs) buffer"
flag tier2 "hanks' balanced salt solution (hbss) buffer"
flag tier2 "earle's balanced salt solution (ebss) buffer"

* --- RNAi mixed/ambiguous (placed conservatively in Tier 2) ---
flag tier2 "gene-specific rnai reagents"

* --- Transfection (EU para 11(iii), section IV.D.2; cleared para 122) ---
flag tier2 "transfection reagents - cellfectin (insect cell)"
flag tier2 "transfection reagents - in vivo delivery reagents"
flag tier2 "transfection reagents - protein transfection reagents"
* --- Chemical transfection variants (one market per EU para 112; Lipofectamine/
*     TurboFect/DharmaFect named at para 119) ---
flag tier2 "transfection reagents - calcium phosphate"
flag tier2 "transfection reagents - cationic lipid"
flag tier2 "transfection reagents - deae-dextran"
flag tier2 "transfection reagents - non-liposomal polymer"
flag tier2 "transfection reagents - pei (bulk)"
* viral transduction: outside para 107's chemical-transfection overlap -> Tier 3
flag tier3 "transfection reagents - lentiviral packaging kits"
flag tier3 "transfection reagents - polybrene (viral transduction)"

* --- NA amplification standalone enzymes (EU para 11(iv), section IV.D.3;
*     paras 142, 152, 159, 165, 175 cleared) ---
flag tier2 "high-fidelity dna polymerase"
flag tier2 "high-fidelity hot start dna polymerase"
flag tier2 "high-fidelity hot start pcr systems"
flag tier2 "high-fidelity pcr systems"
flag tier2 "hot start pcr systems"
flag tier2 "hot start taq polymerase"
flag tier2 "reverse transcriptase"
flag tier2 "taq polymerases"

* --- NA amplification ready-to-use kits (EU para 12(iv), para 135 list:
*     PCR kits, dye/probe-based qPCR kits, cDNA synthesis kits, RT-PCR kits,
*     dye/probe-based RT-qPCR kits) ---
flag tier2 "pcr systems"
flag tier2 "dye-based qpcr systems"
flag tier2 "probe-based qpcr systems"
flag tier2 "dye-based rt-qpcr systems"
flag tier2 "probe-based rt-qpcr systems"
flag tier2 "rt-pcr systems"
flag tier2 "first-strand cdna synthesis systems"
flag tier2 "long template pcr systems"
flag tier2 "tissue pcr systems"
flag tier2 "microrna reverse transcription kit"
flag tier2 "pre amplification kits"
flag tier2 "qrt-pcr titration kit"

* --- NA purification kits: para-9 consumables, never market-defined (para 180:
*     affected purification markets are instruments + gel boxes); real TF/LT
*     overlap -> Tier 3 bundled (M.5264 para 75: Qiagen [40-50]% vs combined
*     [5-10]%); magnetic kits stay Tier 2 (fn 127, para 210) ---
flag tier3 "column-based dna and rna extraction kits"
flag tier3 "column-based dna genomic purification kits"
flag tier3 "column-based dna plasmid gigaprep"
flag tier3 "column-based dna plasmid maxiprep"
flag tier3 "column-based dna plasmid megaprep"
flag tier3 "column-based dna plasmid midiprep"
flag tier3 "column-based dna plasmid miniprep"
flag tier3 "column-based dna purification kits"
flag tier3 "column-based gel dna extraction kits"
flag tier3 "column-based gel rna extraction kits"
flag tier3 "column-based microbial dna purification kits"
flag tier3 "column-based pcr and gel purification kit"
flag tier3 "column-based pcr purification kits"
flag tier3 "column-based pcr purification reagent"
flag tier3 "column-based plant dna purification kits"
flag tier3 "column-based plant rna purification kits"
flag tier3 "column-based protein purification kit"
flag tier3 "column-based rna purification kits"
flag tier3 "column-based yeast dna purification kits"
flag tier3 "liquid-based dna plasmid purification kit"
flag tier2 "magnetic-bead based purification kit"
flag tier2 "magnetic bacterial rna purification kit"
flag tier2 "magnetic bead-based mrna selection kit"
flag tier3 "rna extraction reagents"
flag tier3 "rna stabilization reagent"
flag tier3 "silica bead based gel purification kit"
flag tier3 "spin columns"

* --- Molecular weight standards (EU para 11(v), paras 197-201) ---
flag tier2 "pre-stained dna ladders"
flag tier2 "pre-stained protein molecular-weight ladder"
flag tier2 "pre-stained rna ladders"
flag tier2 "unstained dna ladders"
flag tier2 "unstained protein molecular-weight ladder"
flag tier2 "unstained rna ladders"
flag tier2 "rna ladder"
flag tier2 "protein ladders"
flag tier2 "radiolabeled protein molecular-weight ladder"

* --- Cloning enzymes (restriction + modifying; EU para 12(vi), paras 202-207) ---
flag tier2 "restriction enzymes"
flag tier2 "dnase i"
flag tier2 "rnase"
flag tier2 "rnase inhibitors"
flag tier2 "nuclease enzymes"
flag tier2 "taq dna ligases"
flag tier2 "nucleic acid modifying enzymes - alkaline phosphatases"
flag tier2 "nucleic acid modifying enzymes - dna fragmentases"
flag tier2 "nucleic acid modifying enzymes - dna methylases"
flag tier2 "nucleic acid modifying enzymes - end repair enzymes"
flag tier2 "nucleic acid modifying enzymes - endonucleases"
flag tier2 "nucleic acid modifying enzymes - exonucleases"
flag tier2 "nucleic acid modifying enzymes - klenow fragment"
flag tier2 "nucleic acid modifying enzymes - other"
flag tier2 "nucleic acid modifying enzymes - other dna polymerases"
flag tier2 "nucleic acid modifying enzymes - other nucleases"
flag tier2 "nucleic acid modifying enzymes - poly(a) polymerases"
flag tier2 "nucleic acid modifying enzymes - pyrophosphatases"
flag tier2 "nucleic acid modifying enzymes - recombinases"
flag tier2 "nucleic acid modifying enzymes - single-stranded dna binding proteins"
flag tier2 "nucleic acid modifying enzymes - t4 dna ligase"
flag tier2 "nucleic acid modifying enzymes - t4 dna polymerase"
flag tier2 "nucleic acid modifying enzymes - t4 polynucleotide kinase"
flag tier2 "nucleic acid modifying enzymes - t4 dna ligase buffer"
flag tier2 "nucleic acid modifying enzymes - t4 polynucleotide kinase buffer"
flag tier2 "nucleic acid modifying enzymes - t4 rna ligase buffer"
flag tier2 "nucleic acid modifying enzymes - t4 rna ligase"
flag tier2 "nucleic acid modifying enzymes - t7 dna ligase"
flag tier2 "nucleic acid modifying enzymes - taq dna ligase"
flag tier2 "nucleic acid modifying enzymes - terminal transferase"
flag tier2 "nucleic acid modifying enzymes - topoisomerases"
flag tier2 "nucleic acid modifying enzymes - transposases"
* (Excluded: creatine kinase by category-name flag "non-nucleic acid enzyme".
*  Enzyme reaction buffers retained as Tier 2 standard reagents (para 126,
*  named market).)

* --- Cloning kits (EU para 12(vi), para 205) ---
flag tier2 "blunt-end cloning kits"
flag tier2 "directional topo cloning kits"
flag tier2 "gateway cloning kits"
flag tier2 "rapid dna ligation kits"
flag tier2 "seamless cloning kits"
flag tier2 "ta cloning kits"
flag tier2 "topo ta cloning kits"
flag tier2 "zero blunt topo cloning kits"

* --- Cloning-adjacent: bacterial transformation (cloning workflow, not named
*     in paras 202-207) ---
flag tier3 "chemically competent cells"
flag tier3 "electrocompetent cells"
flag tier3 "bacterial transformation reagents"
flag tier3 "expression plasmids"
flag tier3 "plasmid vectors"

* --- Mutagenesis (cloning workflow, not named in paras 202-207) ---
flag tier3 "site-directed mutagenesis systems"
flag tier3 "site-directed mutagenesis kits"
flag tier3 "transposon mutagenesis kits"

* --- SDS-PAGE (EU para 12(vii), paras 302-306; named: vertical gel boxes,
*     power suppliers, pre-cast gels, standards, gel stains) ---
flag tier2 "horizontal electrophoresis systems"  // para 12(v), para 180
* acrylamide/bis + casting kit: outside para 303's closed SDS-PAGE list -> Tier 3
flag tier3 "acrylamide/bis solution"
flag tier3 "polyacrylamide gels casting kit"
flag tier2 "pre-cast bis-tris gels"
flag tier2 "pre-cast tbe gels"
flag tier2 "pre-cast tris-acetate gels"
flag tier2 "pre-cast tris-glycine gels"
flag tier2 "pre-cast tris-hcl gels"
flag tier2 "pre-cast tris-tricine gels"
flag tier2 "protein gel stains"
flag tier2 "nucleic acid gel stains"
flag tier2 "vertical electrophoresis systems"

* --- Western blotting: TRANSFER BOXES, MEMBRANES, CHEMILUM SUBSTRATES ONLY
*     (EU para 307 narrowly defines this overlap) ---
flag tier2 "chemiluminescent substrates"
flag tier2 "chemiluminescent western blot detection"
flag tier2 "nitrocellulose blotting membranes"
flag tier2 "precut nitrocellulose transfer blotting packs"
flag tier2 "precut pvdf transfer blotting packs"
flag tier2 "pvdf blotting membranes"
flag tier2 "western blot boxes"

* --- Protein modification (EU para 12(ix), paras 313-317;
*     chemical modification, cross-linking, proteases) ---
flag tier2 "antibody labeling kits"
flag tier2 "bioconjugation reagents"
flag tier2 "crosslinking reagents"
flag tier2 "protein and antibody labeling kits"
flag tier2 "protein modifying enzymes"

* --- Reactive dyes (EU para 12(x), paras 318-321) ---
*     STRICT: only "reactive dyes" — amine/thiol-reactive activated fluorophores.
*     General fluorophores, NA stains, indicator dyes are NOT reactive dyes.
flag tier2 "fluorophore - bioconjugate dyes"

count if tier2 == 1

*-------------------------------------------------------------------------------
* TIER 3: BUNDLING / EXTENSION ROBUSTNESS
*-------------------------------------------------------------------------------

* --- Cell culture supplements (bundled with HyClone media) ---
flag tier3 "cell culture nutritional supplements - amino acids"
flag tier3 "cell culture nutritional supplements - b27"
flag tier3 "cell culture nutritional supplements - casamino acids"
flag tier3 "cell culture nutritional supplements - glucose"
flag tier3 "cell culture nutritional supplements - insulin"
flag tier3 "cell culture nutritional supplements - its-g"
flag tier3 "cell culture nutritional supplements - l-glutamine"
flag tier3 "cell culture nutritional supplements - lif"
flag tier3 "cell culture nutritional supplements - other"
flag tier3 "cell culture nutritional supplements - peptone"
flag tier3 "cell culture nutritional supplements - sodium pyruvate"
flag tier3 "cell culture nutritional supplements - sugars"
flag tier3 "cell culture nutritional supplements - tryptone"
flag tier3 "cell culture nutritional supplements - vitamins"
flag tier3 "cell culture nutritional supplements - yeast"
flag tier3 "cell culture dissociation reagents"
flag tier3 "growth medium supplement"

* --- End-user magnetic beads (EU beads section paras 250-278: overlap named;
*     serious doubts + OEM divestiture confined to OEM supply, so end-user
*     side = named overlap, no serious doubts -> Tier 2) ---
flag tier2 "affinity resins - activated coupling matrices (magnetic)"
flag tier2 "affinity resins - anti-ig secondary (magnetic)"
flag tier2 "affinity resins - epitope tags (flag/ha/myc/v5) (magnetic)"
flag tier2 "affinity resins - glycoprotein (lectin-immobilized) (magnetic)"
flag tier2 "affinity resins - gst-tag (magnetic)"
flag tier2 "affinity resins - his-tag (imac) (magnetic)"
flag tier2 "affinity resins - mbp-tag (magnetic)"
flag tier2 "affinity resins - other (magnetic)"
flag tier2 "affinity resins - protein a (magnetic)"
flag tier2 "affinity resins - protein a/g (magnetic)"
flag tier2 "affinity resins - protein g (magnetic)"
flag tier2 "affinity resins - strep-tag (magnetic)"
flag tier2 "affinity resins - streptavidin/avidin (magnetic)"
flag tier2 "immunomagnetic cell separation beads"
flag tier2 "immunomagnetic cell separation columns"
flag tier2 "magnetic beads - other"
flag tier2 "magnetic cell separation kits"
flag tier2 "magnetic ip kit"

* --- Electrophoresis sample/running buffers (bundled with Tier 2 SDS-PAGE) ---
flag tier3 "laemmli sample buffer"
flag tier3 "lds sample buffer"
flag tier3 "mes-sds buffer"
flag tier3 "mops-sds buffer"
flag tier3 "native page running buffers"
flag tier3 "native-page sample buffer"
flag tier3 "reducing agents - bme"
flag tier3 "tbe buffer"
flag tier3 "tris-aceate-sds running buffer"  // sic: data spells "aceate"
flag tier3 "tris-acetate-edta (tae) buffer"
flag tier3 "tris-glycine buffer"
flag tier3 "tris-glycine-sds (tgs) buffer"
flag tier3 "tris-tricine-sds buffer"

* --- Western blot membrane-adjacent consumables (papers and transfer buffers
*     are pre-/at-transfer; EU para 307 transfer-step overlap) ---
flag tier3 "gel blotting papers"
flag tier3 "western blot transfer buffers"

* --- IVT specialty kits (cloning workflow extension) ---
flag tier3 "capped mrna synthesis kits"
flag tier3 "in vitro transcription kit"
flag tier3 "rna polymerases"
flag tier3 "direct pcr lysis reagents"

* --- BSA: bovine-derived (shares input with Tier 1 FBS); HyClone sold BSA as
*     part of cell-culture portfolio; co-purchased with FBS as serum
*     supplement/blocker (bundling) ---
flag tier3 "bovine serum albumin"

count if tier3 == 1
assert tier1 + tier2 + tier3 <= 1
gen treated_strict = (tier1 == 1)
gen treated_1and2  = (tier1 == 1 | tier2 == 1)

label var tier1          "Tier 1: serious-doubts finding (EU paras 41/69/98/105/278) or FTC Dharmacon"
label var tier2          "Tier 2: named overlap, no serious doubts (EU paras 11, 12, fn 44)"
label var tier3          "Tier 3: bundling / extension robustness"
label var treated_strict "Treated (Tier 1 only)"
label var treated_1and2  "Treated (Tier 1 + Tier 2)"

tab tier1
tab tier2
tab tier3
tab treated_strict
tab treated_1and2

gen bad_control = 0
gen bad_control_reason = ""
* Rule: bad_control = US-based exogenous shock to price/spending during
* 2010-2018, OR a product where Thermo and Life Tech had genuine
* horizontal overlap pre-merger (so bundling/portfolio effects bias the
* control), OR classification ambiguity. Bundling alone (without horizontal
* overlap) is NOT sufficient -- those belong in Tier 3.

* --- Antibody market shocks: reproducibility crisis 2014-16 + Sigma-Aldrich
*     -> MilliporeSigma merger Nov 2015 absorbed one of the largest antibody
*     portfolios in the industry ---
flag bad_control "primary antibodies" "secondary antibodies"
replace bad_control_reason = "antibody reproducibility crisis 2014-16; Sigma-Aldrich/MilliporeSigma merger Nov 2015 affected major antibody supplier" ///
    if inlist(category, "primary antibodies", "secondary antibodies")

* --- Avidin products: Thermo (Pierce NeutrAvidin) AND Life (Molecular Probes
*     streptavidin conjugates) both had strong franchises -> horizontal
*     overlap from the merger ---
flag bad_control "avidin products"
replace bad_control_reason = "horizontal overlap pre-merger: Pierce biotin-avidin franchise + Molecular Probes streptavidin-fluor conjugates" ///
    if category == "avidin products"

* --- Phosphoprotein electrophoresis reagents: ambiguous classification
*     (Tier 2 -> control in changelog); flag rather than contaminate either group ---
flag bad_control "phosphoprotein electrophoresis reagents"
replace bad_control_reason = "classification uncertainty - not shock-based; specialty SDS-PAGE reagent overlapping with Tier 2 protein workflow" ///
    if category == "phosphoprotein electrophoresis reagents"

*-------------------------------------------------------------------------------
* US-based exogenous shocks during 2010-2018 window
*-------------------------------------------------------------------------------

* --- Acetonitrile: Hurricane Ike (Sep 2008) hit BP/INEOS Texas Gulf plant,
*     one of few US producers; global ACN shortage with lingering US price
*     effects through 2010-2011 ---
flag bad_control "acetonitrile"
replace bad_control_reason = "US shock: Hurricane Ike (2008) hit Texas Gulf ACN production; global shortage with lingering US price effects 2010-2011" ///
    if category == "acetonitrile"

* --- Nitrile gloves: 2017-2018 NBR (nitrile butadiene rubber) feedstock
*     shortage drove ~20-40% US lab glove price hikes; Malaysian production
*     consolidation ---
flag bad_control "nitrile gloves"
replace bad_control_reason = "US-relevant shock: 2017-2018 NBR feedstock shortage drove 20-40% lab glove price increases" ///
    if category == "nitrile gloves"

* --- Synthetic DNA oligonucleotides + dual-labeled probes: US-driven secular
*     price collapse from Twist Bioscience entry (founded 2013, SF) and IDT
*     (Coralville IA) scale-up; per-base costs fell ~10x in window ---
flag bad_control "synthetic dna oligonucleotide - desalted" "synthetic dual-labeled probe"
replace bad_control_reason = "US-driven secular price collapse: Twist Bioscience entry 2013 + IDT scale-up dropped per-base costs ~10x in window" ///
    if inlist(category, "synthetic dna oligonucleotide - desalted", "synthetic dual-labeled probe")

* --- Filtration (bottle top, syringe, centrifugal ultrafiltration): Pall Corp
*     (Port Washington NY) -> Danaher (closed Aug 2015), US M&A overlapping
*     the TF/Life window ---
flag bad_control "bottle top filters" "syringe filters" "centrifugal ultrafiltration devices"
replace bad_control_reason = "US M&A in window: Pall Corp -> Danaher (closed Aug 2015) reshuffled US lab filtration market" ///
    if inlist(category, "bottle top filters", "syringe filters", "centrifugal ultrafiltration devices")

* --- Needles and syringes: Becton Dickinson (Franklin Lakes NJ) + CareFusion
*     (San Diego CA) closed Mar 2015; BD dominates US needle/syringe ---
flag bad_control "hypodermic needles" "syringes"
replace bad_control_reason = "US M&A in window: Becton Dickinson + CareFusion closed Mar 2015; BD dominates US needle/syringe" ///
    if inlist(category, "hypodermic needles", "syringes")

* --- Formaldehyde / paraformaldehyde: US-specific regulatory tightening -
*     EPA IRIS draft assessment 2010, NTP 12th Report on Carcinogens (Jun 2011)
*     listed as known human carcinogen, OSHA exposure tightening ---
flag bad_control "formaldehydes and paraformaldehydes"
replace bad_control_reason = "US regulatory shock: EPA IRIS 2010, NTP 12th RoC 2011 listed as known human carcinogen, OSHA tightening" ///
    if category == "formaldehydes and paraformaldehydes"

* --- Ethanol: US corn ethanol commodity exposure - 2012 Midwest drought,
*     RFS waiver fights 2012-2014, EPA RFS proposal Nov 2013 ---
flag bad_control "ethanol"
replace bad_control_reason = "US commodity shock: 2012 Midwest drought + RFS volatility 2012-2014 moved corn-ethanol prices" ///
    if category == "ethanol"

count if bad_control == 1
tab bad_control

label var bad_control        "Drop from controls: action/shock/bundling in 2010-2018 window"
label var bad_control_reason "Reason category was flagged as bad control"
gen keep = (support >= 25 & precision >= 0.8 & recall >= 0.8) //| (inrange(support, 10, 25) & precision >= 0.9 & recall >=0.90)
* --- shRNA: Tier 2 treated but removed from sample entirely (via keep = 0) ---
flag bad_control "synthetic shrna"
replace bad_control_reason = "tier 2 treated but excluded: CRISPR substitute entry (Cas9 2013, GeCKO libraries 2014) hit knockdown screening at merger date; merger pricing effect not separable from technology substitution" ///
    if category == "synthetic shrna"

* --- Undocumented horizontal overlap (same logic as avidin) ---
flag bad_control "slide mounting medium"
replace bad_control_reason = "horizontal overlap pre-merger: Molecular Probes ProLong/SlowFade antifade mountants (Life) + Richard-Allan/Shandon histology mounting media (Thermo)" ///
    if category == "slide mounting medium"
flag bad_control "ldh cytotoxicity assay"
replace bad_control_reason = "horizontal overlap pre-merger: Pierce LDH cytotoxicity assay (Thermo) + Invitrogen/Molecular Probes cytotoxicity assay lines (Life)" ///
    if category == "ldh cytotoxicity assay"
*   flag bad_control "colorimetric substrates - tmb"  (Pierce TMB + Invitrogen/
*     Novex ELISA substrates overlap; substitute for Tier 2 chemilum substrates)
*   flag bad_control "cell lysis detergents - tween detergents"  (Pierce/
*     Invitrogen lysis reagent overlap)
flag bad_control "cell lysis detergents - np-40 (igepal ca-630)"
replace bad_control_reason = "horizontal overlap pre-merger: Pierce surfactants/lysis buffers (Thermo) + Invitrogen lysis reagents (Life)" ///
    if category == "cell lysis detergents - np-40 (igepal ca-630)"

* --- Substitutes for treated markets (demand spillover contaminates control) ---
flag bad_control "human serum"
replace bad_control_reason = "substitute for Tier 1 FBS in cell culture; merger-induced FBS price changes shift demand" ///
    if category == "human serum"
flag bad_control "centrifugation media"
replace bad_control_reason = "Ficoll/Percoll density-gradient cell separation substitutes for magnetic bead-based separation (Dynabeads, Life)" ///
    if category == "centrifugation media"

* --- US-based shocks in window ---
flag bad_control "gene expression inducers"
replace bad_control_reason = "US shock: doxycycline (standard Tet-On/Off inducer) generic price spike 2013-14" ///
    if category == "gene expression inducers"
flag bad_control "drug - anticoagulant"
replace bad_control_reason = "US shock: heparin Chinese crude API cost pressure through window; US shortage from 2017" ///
    if category == "drug - anticoagulant"
flag bad_control "bacterial selection antibiotics - rifampicin"
replace bad_control_reason = "US shock: rifampin on FDA drug-shortage list 2013-14 and 2017" ///
    if category == "bacterial selection antibiotics - rifampicin"
flag bad_control "sucrose"
replace bad_control_reason = "US shock: AD/CVD case vs Mexican sugar (filed Mar 2014, suspension agreements Dec 2014) + 2012 drought; also ambiguous with Tier 3 supplements-sugars" ///
    if category == "sucrose"
flag bad_control "dextrose"
replace bad_control_reason = "US commodity shock: corn exposure, 2012 Midwest drought (parallel to ethanol); also ambiguous with Tier 3 supplements-glucose" ///
    if category == "dextrose"
flag bad_control "citric acid"
replace bad_control_reason = "US trade shock: antidumping orders on Chinese citric acid in force through window; new AD/CVD investigations 2017, orders 2018" ///
    if category == "citric acid"
flag bad_control "formic acid"
replace bad_control_reason = "industrial commodity priced off petrochemical feedstocks; 2014-15 oil price collapse coincides with merger" ///
    if category == "formic acid"
flag bad_control "nitrogen"
replace bad_control_reason = "US M&A in window: Air Liquide-Airgas closed May 2016, Praxair-Linde announced 2016; prices track energy" ///
    if category == "nitrogen"
flag bad_control "capillary blood collection tubes"
replace bad_control_reason = "US M&A in window: BD (Microtainer) dominates; BD-CareFusion closed Mar 2015 (same reason as needles/syringes)" ///
    if category == "capillary blood collection tubes"
flag bad_control "crystallizing dishes"
replace bad_control_reason = "US M&A in window: Kimble + Wheaton + Duran merged into DWK Life Sciences 2017; Corning absorbed BD Discovery Labware Oct 2012" ///
    if category == "crystallizing dishes"

* --- Classification ambiguity with treated families / merged-firm dominance ---
flag bad_control "pipes buffers" "egta solution"
replace bad_control_reason = "classification ambiguity: prepared buffer solution in same family as Tier 2 process liquids (PBS/TE/HBSS/EBSS)" ///
    if inlist(category, "pipes buffers", "egta solution")
flag bad_control "collagenase"
replace bad_control_reason = "classification ambiguity: is a cell culture dissociation reagent, a Tier 3 category (Gibco collagenase)" ///
    if category == "collagenase"
flag bad_control "cell culture antibiotics - blasticidin"
replace bad_control_reason = "Invitrogen-dominant selection antibiotic tied to Tier 3 expression plasmid/vector systems; portfolio pricing exposure" ///
    if category == "cell culture antibiotics - blasticidin"
flag bad_control "cylindrical carboys"
replace bad_control_reason = "Nalgene (Thermo) dominates category; exposed to acquirer portfolio repricing despite no Life overlap" ///
    if category == "cylindrical carboys"

* --- Weaker rationale (judgment calls) ---
flag bad_control "catalase"
replace bad_control_reason = "judgment call: bovine-liver-derived biologic sharing bovine supply chain with FBS/BSA" ///
    if category == "catalase"
flag bad_control "sodium hydride"
replace bad_control_reason = "judgment call: synthetic-chemistry commodity, petrochemical feedstock pricing, non-life-science buyer base" ///
    if category == "sodium hydride"
flag bad_control "dna-salmon sperm"
replace bad_control_reason = "judgment call: hybridization-era blocking agent in secular decline with NGS shift; nominal Invitrogen overlap" ///
    if category == "dna-salmon sperm"
flag bad_control "flash chromatography columns - silica gel"
replace bad_control_reason = "judgment call: synthetic-chemistry product with non-life-science buyer base" ///
    if category == "flash chromatography columns - silica gel"
* Version switch, placed after the named flags so specific reasons win
if "`tier3treated'" != "" {
    gen treated = (tier1 == 1 | tier2 == 1 | tier3 == 1)
    label var treated "Treated (Tiers 1-3)"
    local vtag all3
}
else {
    gen treated = (tier1 == 1 | tier2 == 1)
    label var treated "Treated (Tiers 1-2); tier 3 excluded from both groups"
    replace bad_control = 1 if tier3 == 1
    replace bad_control_reason = "tier 3: bundled/undocumented overlap; excluded from control pool" ///
        if tier3 == 1 & bad_control_reason == ""
    local vtag t12
}
tab treated
replace keep = 0 if bad_control == 1  // drop bad controls from analysis sample
gen excluded_type = cond(bad_control == 0, "", ///
    cond(treated == 1, "excluded treated (own shock)", ///
    cond(tier3 == 1, "tier 3 excluded from both groups", "excluded control")))

foreach v in tier1 tier2 tier3 bad_control {
    quietly count if `v' == 1
    di "`v': " r(N) " categories"
}
if $flag_nomatch > 0 {
    di as error "$flag_nomatch flagged category string(s) matched nothing in the data"
    exit 498
}

* --- Export bad_control documentation CSV ---
preserve
    keep if bad_control == 1
    keep category excluded_type bad_control_reason
    sort category
    export delimited using ../output/bad_control_documentation_`vtag'.csv, replace
    if "`vtag'" == "t12" export delimited using ../output/bad_control_documentation.csv, replace
restore

save ../output/categories_`embed'_`vtag', replace
if "`vtag'" == "t12" save ../output/categories_`embed', replace
end
main
