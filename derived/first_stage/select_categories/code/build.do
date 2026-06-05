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
* TREATED PRODUCT MARKET CLASSIFICATION (STRICT AUDIT)
* Thermo Fisher / Life Technologies Merger
*
* Strict rule: a category is treated only when the antitrust document text
* directly supports the placement.
*   - Tier 1: subject of an EU "serious doubts" finding (EU paras 41, 69, 98,
*             105, 250) OR explicitly named in the FTC Dharmacon Gene Modulation
*             Products definition (FTC Order def. U) for siRNA/miRNA-specific items.
*   - Tier 2: named in EU para 11 (detailed analysis, no doubts) or para 12
*             (mentioned overlap, summary clearance) or otherwise identified
*             as an overlap in the body text of section IV (e.g., footnote 44
*             for non-FBS sera).
*   - Tier 3: bundling/extension robustness (NOT directly antitrust-document-
*             named; co-purchased with Tier 1/Tier 2 products).
*-------------------------------------------------------------------------------
* CHANGELOG vs. previous build.do (strict audit):
*   Tier 1 -> Tier 2:
*     - bovine adult/calf serum, nz bovine calf serum, horse serum (footnote 44)
*     - PBS / DPBS / HBSS (process liquids: EU para 27 separate market;
*       not in serious-doubts finding)
*     - gene-specific rnai reagents (ambiguous between siRNA/shRNA/miRNA)
*   Tier 2 -> control:
*     - pre-designed/custom-designed qpcr assays (oligonucleotides, not kits)
*     - qpcr beads (not in EU kit market list)
*     - nucleic acid quantitation (not in any EU market)
*     - phosphoprotein electrophoresis reagents (specialty)
*     - fluorophore - general / NA stain, NA gel stains, streptavidin conjugates,
*       quantum dots (EU para 318 "reactive dyes" only)
*     - modified/radiolabeled nucleotides (EU para 126 ancillary reagents)
*     - creatine kinase (label flags non-NA enzyme)
*     - all enzyme reaction buffers (EU para 126 buffers excluded)
*     - protein quantitation assay kits (not in EU markets)
*     - pcr barcoding expansion (sequencing library prep)
*   Tier 2 -> Tier 3:
*     - capped mrna synthesis / IVT / direct pcr lysis (specialty derivatives)
*   Tier 3 -> control:
*     - all non-reactive-dye fluorophores (calcium/cell tracer/lysosome/etc.)
*     - viability stains (live-cell imaging)
*     - reaction buffers, ligation reaction buffer (EU para 126)
*     - WB accessories: blockers, enhancers, pen, rollers, stripping buffers
*       (post-transfer; weak bundling link)
*   New additions:
*     - earle's balanced salt solution (ebss) buffer -> Tier 2 (process liquid)
*     - rna ladder, protein ladders, radiolabeled protein MW ladder -> Tier 2
*     - site-directed mutagenesis kits, transposon mutagenesis kits,
*       random mutagenesis systems -> Tier 2 (cloning, EU para 12(vi))
*===============================================================================

gen tier1 = 0
gen tier2 = 0
gen tier3 = 0

*-------------------------------------------------------------------------------
* TIER 1: SERIOUS DOUBTS FINDING IN EU OR FTC GENE MODULATION DIVESTITURE
*-------------------------------------------------------------------------------

* --- Cell culture media (EU para 41 serious doubts; FTC HyClone divested) ---
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

* --- FBS (EU para 69 serious doubts; FTC HyClone divested) ---
*     EU para 58: "main area of overlap is the supply of FBS"
*     Non-FBS sera (calf, adult bovine, equine) -> Tier 2 (footnote 44)
replace tier1 = 1 if category == "australian fbs"
replace tier1 = 1 if category == "canadian fbs"
replace tier1 = 1 if category == "new zealand fbs"
replace tier1 = 1 if category == "us fbs"

* --- siRNA (EU para 98 serious doubts; FTC Dharmacon Gene Modulation
*     Products def. U includes "small/short interfering RNA (siRNA)") ---
replace tier1 = 1 if category == "synthetic sirna"
replace tier1 = 1 if category == "sirna buffers"
replace tier1 = 1 if category == "sirna transfection medium"
replace tier1 = 1 if category == "sirna transfection reagents"

* --- miRNA: no exact "synthetic mirna" category in current data; FTC def. U
*     includes microRNA. (gene-specific rnai reagents is ambiguous -> Tier 2)

count if tier1 == 1

*-------------------------------------------------------------------------------
* TIER 2: NAMED OVERLAP, NO SERIOUS DOUBTS
*-------------------------------------------------------------------------------

* --- shRNA (EU para 88: no serious doubts; bundled in Dharmacon divestiture) ---
replace tier2 = 1 if category == "synthetic shrna"

* --- Non-FBS sera (footnote 44: overlap markets covered by FBS commitment,
*     "not further considered" by EU) ---
replace tier2 = 1 if category == "bovine adult serum"
replace tier2 = 1 if category == "bovine calf serum"
replace tier2 = 1 if category == "nz bovine calf serum"
replace tier2 = 1 if category == "horse serum"
replace tier2= 1 if category == "goat serum"
replace tier2= 1 if category == "donkey serum"
replace tier2= 1 if category == "mouse serum"
replace tier2= 1 if category == "rat serum"
replace tier2= 1 if category == "rabbit serum"
replace tier2= 1 if category == "sheep serum"
* --- Process liquids (EU para 27: separate product market; FTC HyClone
*     divestiture covers them but EU did not analyze for serious doubts) ---
replace tier2 = 1 if category == "phosphate-buffered saline (pbs) buffer"
replace tier2 = 1 if category == "tris-edta (te) buffer"
replace tier2 = 1 if category == "dulbecco's phosphate-buffered saline (dpbs) buffer"
replace tier2 = 1 if category == "hanks' balanced salt solution (hbss) buffer"
replace tier2 = 1 if category == "earle's balanced salt solution (ebss) buffer"

* --- RNAi mixed/ambiguous (placed conservatively in Tier 2) ---
replace tier2 = 1 if category == "gene-specific rnai reagents"

* --- Transfection (EU para 11(iii), section IV.D.2; cleared para 122) ---
replace tier2 = 1 if category == "transfection reagents"
replace tier2 = 1 if category == "transfection reagents - cellfectin (insect cell)"
replace tier2 = 1 if category == "transfection reagents - electroporation kits"
replace tier2 = 1 if category == "transfection reagents - electroporation reagent"
replace tier2 = 1 if category == "transfection reagents - in vivo delivery reagents"
replace tier2 = 1 if category == "transfection reagents - lentiviral packaging kits"
replace tier2 = 1 if category == "transfection reagents - other"
replace tier2 = 1 if category == "transfection reagents - polybrene (viral transduction)"
replace tier2 = 1 if category == "transfection reagents - protein transfection reagents"

* --- NA amplification standalone enzymes (EU para 11(iv), section IV.D.3;
*     paras 142, 152, 159, 165, 175 cleared) ---
replace tier2 = 1 if category == "high-fidelity dna polymerase"
replace tier2 = 1 if category == "high-fidelity hot start dna polymerase"
replace tier2 = 1 if category == "high-fidelity hot start pcr systems"
replace tier2 = 1 if category == "high-fidelity pcr systems"
replace tier2 = 1 if category == "hot start pcr systems"
replace tier2 = 1 if category == "hot start taq polymerase"
replace tier2 = 1 if category == "reverse transcriptase"
replace tier2 = 1 if category == "taq polymerases"

* --- NA amplification ready-to-use kits (EU para 12(iv), para 135 list:
*     PCR kits, dye/probe-based qPCR kits, cDNA synthesis kits, RT-PCR kits,
*     dye/probe-based RT-qPCR kits) ---
replace tier2 = 1 if category == "pcr systems"
replace tier2 = 1 if category == "dye-based qpcr systems"
replace tier2 = 1 if category == "probe-based qpcr systems"
replace tier2 = 1 if category == "dye-based rt-qpcr systems"
replace tier2 = 1 if category == "probe-based rt-qpcr systems"
replace tier2 = 1 if category == "rt-pcr systems"
replace tier2 = 1 if category == "first-strand cdna synthesis systems"
replace tier2 = 1 if category == "long template pcr systems"
replace tier2 = 1 if category == "tissue pcr systems"
replace tier2 = 1 if category == "microrna reverse transcription kit"
replace tier2 = 1 if category == "pre amplification kits"
replace tier2 = 1 if category == "qrt-pcr titration kit"

* --- NA purification kits (EU section IV.D.4, paras 178-201; column-based
*     and magnetic-bead-based finished kits) ---
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
replace tier2 = 1 if category == "magnetic bead-based mrna selection kit"
replace tier2 = 1 if category == "rna extraction reagents"
replace tier2 = 1 if category == "rna stabilization reagent"
replace tier2 = 1 if category == "silica bead based gel purification kit"
replace tier2 = 1 if category == "spin columns"

* --- Molecular weight standards (EU para 11(v), paras 197-201) ---
replace tier2 = 1 if category == "pre-stained dna ladders"
replace tier2 = 1 if category == "pre-stained protein molecular-weight ladder"
replace tier2 = 1 if category == "pre-stained rna ladders"
replace tier2 = 1 if category == "unstained dna ladders"
replace tier2 = 1 if category == "unstained protein molecular-weight ladder"
replace tier2 = 1 if category == "unstained rna ladders"
replace tier2 = 1 if category == "rna ladder"
replace tier2 = 1 if category == "protein ladders"
replace tier2 = 1 if category == "radiolabeled protein molecular-weight ladder"

* --- Cloning enzymes (restriction + modifying; EU para 12(vi), paras 202-207) ---
replace tier2 = 1 if category == "restriction enzymes"
replace tier2 = 1 if category == "dnase i"
replace tier2 = 1 if category == "rnase"
replace tier2 = 1 if category == "rnase inhibitors"
replace tier2 = 1 if category == "nuclease enzymes"
replace tier2 = 1 if category == "rna polymerases"
replace tier2 = 1 if category == "taq dna ligases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - alkaline phosphatases"
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
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 dna polymerase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 polynucleotide kinase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 dna ligase buffer"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 polynucleotide kinase buffer"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 rna ligase buffer"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t4 rna ligase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - t7 dna ligase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - taq dna ligase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - terminal transferase"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - topoisomerases"
replace tier2 = 1 if category == "nucleic acid modifying enzymes - transposases"
* (Excluded: creatine kinase by category-name flag "non-nucleic acid enzyme";
*  enzyme reaction buffers (t4 ligase buffer, t4 PNK buffer, t4 RNA ligase
*  buffer, restriction enzyme buffer) by EU para 126.)

* --- Cloning kits (EU para 12(vi), para 205) ---
replace tier2 = 1 if category == "blunt-end cloning kits"
replace tier2 = 1 if category == "directional topo cloning kits"
replace tier2 = 1 if category == "gateway cloning kits"
replace tier2 = 1 if category == "rapid dna ligation kits"
replace tier2 = 1 if category == "seamless cloning kits"
replace tier2 = 1 if category == "ta cloning kits"
replace tier2 = 1 if category == "topo ta cloning kits"
replace tier2 = 1 if category == "zero blunt topo cloning kits"

* --- Cloning-adjacent: bacterial transformation (cloning workflow) ---
replace tier2 = 1 if category == "chemically competent cells"
replace tier2 = 1 if category == "electrocompetent cells"
replace tier2 = 1 if category == "bacterial transformation reagents"
replace tier2 = 1 if category == "expression plasmids"
replace tier2 = 1 if category == "plasmid vectors"

* --- Mutagenesis (cloning kits per EU para 12(vi)) ---
replace tier2 = 1 if category == "site-directed mutagenesis systems"
replace tier2 = 1 if category == "site-directed mutagenesis kits"
replace tier2 = 1 if category == "transposon mutagenesis kits"
replace tier2 = 1 if category == "random mutagenesis systems"

* --- SDS-PAGE (EU para 12(vii), paras 302-306; named: vertical gel boxes,
*     power suppliers, pre-cast gels, standards, gel stains) ---
replace tier2 = 1 if category == "acrylamide/bis solution"
replace tier2 = 1 if category == "horizontal electrophoresis systems"
replace tier2 = 1 if category == "polyacrylamide gels casting kit"
replace tier2 = 1 if category == "pre-cast bis-tris gels"
replace tier2 = 1 if category == "pre-cast tbe gels"
replace tier2 = 1 if category == "pre-cast tris-acetate gels"
replace tier2 = 1 if category == "pre-cast tris-glycine gels"
replace tier2 = 1 if category == "pre-cast tris-hcl gels"
replace tier2 = 1 if category == "pre-cast tris-tricine gels"
replace tier2 = 1 if category == "protein gel stains"
replace tier2 = 1 if category == "nucleic acid gel stains"
replace tier2 = 1 if category == "vertical electrophoresis systems"

* --- Western blotting: TRANSFER BOXES, MEMBRANES, CHEMILUM SUBSTRATES ONLY
*     (EU para 309 narrowly defines this overlap) ---
replace tier2 = 1 if category == "chemiluminescent substrates"
replace tier2 = 1 if category == "chemiluminescent western blot detection"
replace tier2 = 1 if category == "nitrocellulose blotting membranes"
replace tier2 = 1 if category == "precut nitrocellulose transfer blotting packs"
replace tier2 = 1 if category == "precut pvdf transfer blotting packs"
replace tier2 = 1 if category == "pvdf blotting membranes"
replace tier2 = 1 if category == "western blot boxes"

* --- Protein modification (EU para 12(ix), paras 313-317;
*     chemical modification, cross-linking, proteases) ---
replace tier2 = 1 if category == "antibody labeling kits"
replace tier2 = 1 if category == "bioconjugation reagents"
replace tier2 = 1 if category == "crosslinking reagents"
replace tier2 = 1 if category == "protein and antibody labeling kits"
replace tier2 = 1 if category == "protein modifying enzymes"

* --- Reactive dyes (EU para 12(x), paras 318-321) ---
*     STRICT: only "reactive dyes" — amine/thiol-reactive activated fluorophores.
*     General fluorophores, NA stains, indicator dyes are NOT reactive dyes.
replace tier2 = 1 if category == "fluorophore - bioconjugate dyes"

count if tier2 == 1

*-------------------------------------------------------------------------------
* TIER 3: BUNDLING / EXTENSION ROBUSTNESS
*-------------------------------------------------------------------------------

* --- Cell culture supplements (bundled with HyClone media) ---
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

* --- End-user magnetic beads (NOT in EU OEM divestiture; bundling robustness) ---
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
replace tier3 = 1 if category == "mes-sds buffer"
replace tier3 = 1 if category == "mops-sds buffer"
replace tier3 = 1 if category == "native page running buffers"
replace tier3 = 1 if category == "native-page sample buffer"
replace tier3 = 1 if category == "reducing agents - bme"
replace tier3 = 1 if category == "tbe buffer"
replace tier3 = 1 if category == "tris-aceate-sds running buffer"
replace tier3 = 1 if category == "tris-acetate-edta (tae) buffer"
replace tier3 = 1 if category == "tris-glycine buffer"
replace tier3 = 1 if category == "tris-glycine-sds (tgs) buffer"
replace tier3 = 1 if category == "tris-tricine-sds buffer"

* --- Western blot membrane-adjacent consumables (papers and transfer buffers
*     are pre-/at-transfer; EU para 309 transfer-step overlap) ---
replace tier3 = 1 if category == "gel blotting papers"
replace tier3 = 1 if category == "western blot transfer buffers"

* --- IVT specialty kits (cloning workflow extension) ---
replace tier3 = 1 if category == "capped mrna synthesis kits"
replace tier3 = 1 if category == "in vitro transcription kit"
replace tier3 = 1 if category == "direct pcr lysis reagents"

* --- BSA: bovine-derived (shares input with Tier 1 FBS); HyClone sold BSA as
*     part of cell-culture portfolio; co-purchased with FBS as serum
*     supplement/blocker (bundling) ---
replace tier3 = 1 if category == "bovine serum albumin"

count if tier3 == 1
gen treated_strict = (tier1 == 1)
gen treated_1and2  = (tier1 == 1 | tier2 == 1)
gen treated        = (tier1 == 1 | tier2 == 1 | tier3 == 1)

label var tier1          "Tier 1: serious-doubts finding (EU paras 41/69/98/105) or FTC Dharmacon"
label var tier2          "Tier 2: named overlap, no serious doubts (EU paras 11, 12, fn 44)"
label var tier3          "Tier 3: bundling / extension robustness"
label var treated_strict "Treated (Tier 1 only)"
label var treated_1and2  "Treated (Tier 1 + Tier 2)"
label var treated        "Treated (Tier 1 + Tier 2 + Tier 3)"

tab tier1
tab tier2
tab tier3
tab treated_strict
tab treated_1and2
tab treated

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
replace bad_control = 1 if inlist(category, "primary antibodies", "secondary antibodies")
replace bad_control_reason = "antibody reproducibility crisis 2014-16; Sigma-Aldrich/MilliporeSigma merger Nov 2015 affected major antibody supplier" ///
    if inlist(category, "primary antibodies", "secondary antibodies")

* --- Avidin products: Thermo (Pierce NeutrAvidin) AND Life (Molecular Probes
*     streptavidin conjugates) both had strong franchises -> horizontal
*     overlap from the merger ---
replace bad_control = 1 if category == "avidin products"
replace bad_control_reason = "horizontal overlap pre-merger: Pierce biotin-avidin franchise + Molecular Probes streptavidin-fluor conjugates" ///
    if category == "avidin products"

* --- Phosphoprotein electrophoresis reagents: ambiguous classification
*     (Tier 2 -> control in changelog); flag rather than contaminate either group ---
replace bad_control = 1 if category == "phosphoprotein electrophoresis reagents"
replace bad_control_reason = "classification uncertainty - not shock-based; specialty SDS-PAGE reagent overlapping with Tier 2 protein workflow" ///
    if category == "phosphoprotein electrophoresis reagents"

*-------------------------------------------------------------------------------
* US-based exogenous shocks during 2010-2018 window
*-------------------------------------------------------------------------------

* --- Acetonitrile: Hurricane Ike (Sep 2008) hit BP/INEOS Texas Gulf plant,
*     one of few US producers; global ACN shortage with lingering US price
*     effects through 2010-2011 ---
replace bad_control = 1 if category == "acetonitrile"
replace bad_control_reason = "US shock: Hurricane Ike (2008) hit Texas Gulf ACN production; global shortage with lingering US price effects 2010-2011" ///
    if category == "acetonitrile"

* --- Nitrile gloves: 2017-2018 NBR (nitrile butadiene rubber) feedstock
*     shortage drove ~20-40% US lab glove price hikes; Malaysian production
*     consolidation ---
replace bad_control = 1 if category == "nitrile gloves"
replace bad_control_reason = "US-relevant shock: 2017-2018 NBR feedstock shortage drove 20-40% lab glove price increases" ///
    if category == "nitrile gloves"

* --- Synthetic DNA oligonucleotides + dual-labeled probes: US-driven secular
*     price collapse from Twist Bioscience entry (founded 2013, SF) and IDT
*     (Coralville IA) scale-up; per-base costs fell ~10x in window ---
replace bad_control = 1 if inlist(category, "synthetic dna oligonucleotide - desalted", "synthetic dual-labeled probe")
replace bad_control_reason = "US-driven secular price collapse: Twist Bioscience entry 2013 + IDT scale-up dropped per-base costs ~10x in window" ///
    if inlist(category, "synthetic dna oligonucleotide - desalted", "synthetic dual-labeled probe")

* --- Filtration (bottle top, syringe, centrifugal ultrafiltration): Pall Corp
*     (Port Washington NY) -> Danaher (closed Aug 2015), US M&A overlapping
*     the TF/Life window ---
replace bad_control = 1 if inlist(category, "bottle top filters", "syringe filters", "centrifugal ultrafiltration devices")
replace bad_control_reason = "US M&A in window: Pall Corp -> Danaher (closed Aug 2015) reshuffled US lab filtration market" ///
    if inlist(category, "bottle top filters", "syringe filters", "centrifugal ultrafiltration devices")

* --- Needles and syringes: Becton Dickinson (Franklin Lakes NJ) + CareFusion
*     (San Diego CA) closed Mar 2015; BD dominates US needle/syringe ---
replace bad_control = 1 if inlist(category, "hypodermic needles", "syringes")
replace bad_control_reason = "US M&A in window: Becton Dickinson + CareFusion closed Mar 2015; BD dominates US needle/syringe" ///
    if inlist(category, "hypodermic needles", "syringes")

* --- Formaldehyde / paraformaldehyde: US-specific regulatory tightening -
*     EPA IRIS draft assessment 2010, NTP 12th Report on Carcinogens (Jun 2011)
*     listed as known human carcinogen, OSHA exposure tightening ---
replace bad_control = 1 if category == "formaldehydes and paraformaldehydes"
replace bad_control_reason = "US regulatory shock: EPA IRIS 2010, NTP 12th RoC 2011 listed as known human carcinogen, OSHA tightening" ///
    if category == "formaldehydes and paraformaldehydes"

* --- Ethanol: US corn ethanol commodity exposure - 2012 Midwest drought,
*     RFS waiver fights 2012-2014, EPA RFS proposal Nov 2013 ---
replace bad_control = 1 if category == "ethanol"
replace bad_control_reason = "US commodity shock: 2012 Midwest drought + RFS volatility 2012-2014 moved corn-ethanol prices" ///
    if category == "ethanol"

count if bad_control == 1
tab bad_control

label var bad_control        "Drop from controls: action/shock/bundling in 2010-2018 window"
label var bad_control_reason "Reason category was flagged as bad control"
gen keep = (support >= 25 & precision >= 0.8 & recall >= 0.8) //| (inrange(support, 10, 25) & precision >= 0.9 & recall >=0.90)
replace bad_control = 1 if category == "pipes buffers"  
replace bad_control = 1 if category == "synthetic shrna"  
replace bad_control =1 if inlist(category, "slide mounting medium", "collagenase", "catalase", "dextrose", "egta solution", "pipes buffers", "bacterial selection antibiotics - rifampicin")
replace bad_control =1 if inlist(category, "drug - anticoagulant", "sodium hydride", "crystallizing dishes", "citric acid", "formic acid", "gene expression inducers", "dna-salmon sperm")
replace bad_control =1 if inlist(category, "sucrose", "cell lysis - tween detergents", "flash chromatography columns - silica gel", "cylindrical carboys", "cell culture antibiotics - blasticidin")
replace bad_control =1 if inlist(category, "nitrogen", "centrifugation media", "ldh cytotoxicity assay", "cell lysis detergents - np-40 (igepal ca-630)", "cell lysis detergents" , "human serum", "colorimetric substrates - TMB", "capillary blood collection tubes")
replace keep = 0 if bad_control == 1  // drop bad controls from analysis sample

* --- Export bad_control documentation CSV ---
preserve
    keep if bad_control == 1
    keep category bad_control bad_control_reason
    sort category
    export delimited using ../output/bad_control_documentation.csv, replace
restore

save ../output/categories_`embed', replace
end
main
