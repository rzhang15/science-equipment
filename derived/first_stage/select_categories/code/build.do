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
* TREATED PRODUCT MARKET CLASSIFICATION — FINAL VERSION
* Thermo Fisher / Life Technologies Merger
*
* Classification rule: treated ONLY if the product market is mentioned
* in antitrust documents (EU COMP/M.6944, FTC Complaint, China MOFCOM)
* as an area of overlap. Tier 3 = ancillary products directly bundled
* with documented overlap markets.
*
* Tier 1 (Definitely treated — divestitures required):  41
* Tier 2 (Likely treated — EU confirmed overlap, cleared): 121
* Tier 3 (Bundled with documented overlap markets):        37
* Control (not treated):                                   790
*===============================================================================

gen tier1 = 0
gen tier2 = 0
gen tier3 = 0

*---------------------------------------------------------------
* TIER 1: DEFINITELY TREATED (divestitures required)
*   Cell culture media, sera/FBS, siRNA/gene silencing,
*   magnetic beads (incl. magnetic affinity resins & separation kits)
*---------------------------------------------------------------
replace tier1 = 1 if category == "affinity resins - activated coupling matrices (magnetic)"
replace tier1 = 1 if category == "australian fbs"
replace tier1 = 1 if category == "bovine adult serum"
replace tier1 = 1 if category == "canadian fbs"
replace tier1 = 1 if category == "dmem/f-12"
replace tier1 = 1 if category == "affinity resins - anti-ig secondary (magnetic)"
replace tier1 = 1 if category == "affinity resins - biotin/avidin (magnetic)"
replace tier1 = 1 if category == "affinity resins - epitope tags (flag/ha/myc/v5) (magnetic)"
replace tier1 = 1 if category == "affinity resins - glycoprotein (lectin-immobilized) (magnetic)"
replace tier1 = 1 if category == "affinity resins - gst-tag (magnetic)"
replace tier1 = 1 if category == "affinity resins - his-tag (imac) (magnetic)"
replace tier1 = 1 if category == "affinity resins - mbp-tag (magnetic)"
replace tier1 = 1 if category == "affinity resins - other (magnetic)"
replace tier1 = 1 if category == "affinity resins - protein a (magnetic)"
replace tier1 = 1 if category == "affinity resins - protein a/g (magnetic)"
replace tier1 = 1 if category == "affinity resins - protein g (magnetic)"
replace tier1 = 1 if category == "affinity resins - strep-tag (magnetic)"
replace tier1 = 1 if category == "affinity resins - streptavidin/avidin (magnetic)"
replace tier1 = 1 if category == "basal medium eagle"
replace tier1 = 1 if category == "bovine calf serum"
replace tier1 = 1 if category == "dmem"
replace tier1 = 1 if category == "dry basal media, not chemically defined"
replace tier1 = 1 if category == "gene-specific rnai reagents"
replace tier1 = 1 if category == "hams f12"
replace tier1 = 1 if category == "imdm"
replace tier1 = 1 if category == "immunomagnetic cell separation beads"
replace tier1 = 1 if category == "immunomagnetic cell separation columns"
replace tier1 = 1 if category == "insect cell media"
replace tier1 = 1 if category == "leibovitz l15 media"
replace tier1 = 1 if category == "magnetic bead-based mrna selection kit"
replace tier1 = 1 if category == "magnetic beads - other"
replace tier1 = 1 if category == "magnetic cell separation kits"
replace tier1 = 1 if category == "magnetic ip kit"
replace tier1 = 1 if category == "mccoys 5a"
replace tier1 = 1 if category == "mem"
replace tier1 = 1 if category == "neurobasal media"
replace tier1 = 1 if category == "new zealand fbs"
replace tier1 = 1 if category == "optimem"
replace tier1 = 1 if category == "rpmi"
replace tier1 = 1 if category == "sirna buffers"
replace tier1 = 1 if category == "sirna transfection medium"
replace tier1 = 1 if category == "sirna transfection reagents"
replace tier1 = 1 if category == "specialty cell culture media"
replace tier1 = 1 if category == "stem cell media"
replace tier1 = 1 if category == "synthetic crrna"
replace tier1 = 1 if category == "synthetic shrna"
replace tier1 = 1 if category == "synthetic sirna"
replace tier1 = 1 if category == "us fbs"

*---------------------------------------------------------------
* TIER 2: LIKELY TREATED (EU confirmed overlap, cleared)
*   PCR/qPCR, RT/cDNA, cloning, electrophoresis gels/systems,
*   Western blotting, MW standards, protein modification,
*   protein assays, transfection, NA purification, fluorophores
*---------------------------------------------------------------
replace tier2 = 1 if category == "acrylamide/bis solution"
replace tier2 = 1 if category == "antibody labeling kits"
replace tier2 = 1 if category == "bacterial transformation reagents"
replace tier2 = 1 if category == "bioconjugation reagents"
replace tier2 = 1 if category == "blunt-end cloning kits"
replace tier2 = 1 if category == "capped mrna synthesis kits"
replace tier2 = 1 if category == "chemically competent cells"
replace tier2 = 1 if category == "chemiluminescent western blot detection"
replace tier2 = 1 if category == "chemiluminescent substrates"
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
replace tier2 = 1 if category == "crosslinking reagents"
replace tier2 = 1 if category == "custom-designed qpcr assays"
replace tier2 = 1 if category == "direct pcr lysis reagents"
replace tier2 = 1 if category == "directional topo cloning kits"
replace tier2 = 1 if category == "dnase i"
replace tier2 = 1 if category == "dntps"
replace tier2 = 1 if category == "dye-based qpcr systems"
replace tier2 = 1 if category == "electrocompetent cells"
replace tier2 = 1 if category == "expression plasmids"
replace tier2 = 1 if category == "first-strand cdna synthesis systems"
replace tier2 = 1 if category == "fluorophore - bioconjugate dyes"
replace tier2 = 1 if category == "fluorophore - general"
replace tier2 = 1 if category == "fluorophore - nucleic acid stain"
replace tier2 = 1 if category == "gateway cloning kits"
replace tier2 = 1 if category == "gel blotting papers"
replace tier2 = 1 if category == "high-fidelity dna polymerase"
replace tier2 = 1 if category == "high-fidelity hot start dna polymerase"
replace tier2 = 1 if category == "high-fidelity hot start pcr systems"
replace tier2 = 1 if category == "high-fidelity pcr systems"
replace tier2 = 1 if category == "horizontal electrophoresis systems"
replace tier2 = 1 if category == "hot start taq polymerase"
replace tier2 = 1 if category == "hot start pcr systems"
replace tier2 = 1 if category == "in vitro transcription kit"
replace tier2 = 1 if category == "liquid-based dna plasmid purification kit"
replace tier2 = 1 if category == "long template pcr systems"
replace tier2 = 1 if category == "magnetic bacterial rna purification kit"
replace tier2 = 1 if category == "magnetic-bead based purification kit"
replace tier2 = 1 if category == "microrna reverse transcription kit"
replace tier2 = 1 if category == "modified nucleotides"
replace tier2 = 1 if category == "nitrocellulose blotting membranes"
replace tier2 = 1 if category == "nuclease enzymes"
replace tier2 = 1 if category == "nucleic acid gel stains"
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
replace tier2 = 1 if category == "nucleic acid quantitation"
replace tier2 = 1 if category == "pcr barcoding expansion"
replace tier2 = 1 if category == "pcr systems"
replace tier2 = 1 if category == "phosphoprotein electrophoresis reagents"
replace tier2 = 1 if category == "plasmid vectors"
replace tier2 = 1 if category == "polyacrylamide gels casting kit"
replace tier2 = 1 if category == "pre amplification kits"
replace tier2 = 1 if category == "pre-cast bis-tris gels"
replace tier2 = 1 if category == "pre-cast tbe gels"
replace tier2 = 1 if category == "pre-cast tris-acetate gels"
replace tier2 = 1 if category == "pre-cast tris-glycine gels"
replace tier2 = 1 if category == "pre-cast tris-hcl gels"
replace tier2 = 1 if category == "pre-cast tris-tricine gels"
replace tier2 = 1 if category == "pre-designed qpcr assays"
replace tier2 = 1 if category == "pre-stained dna ladders"
replace tier2 = 1 if category == "pre-stained protein molecular-weight ladder"
replace tier2 = 1 if category == "pre-stained rna ladders"
replace tier2 = 1 if category == "precut nitrocellulose transfer blotting packs"
replace tier2 = 1 if category == "precut pvdf transfer blotting packs"
replace tier2 = 1 if category == "probe-based qpcr systems"
replace tier2 = 1 if category == "probe-based rt-qpcr systems"
replace tier2 = 1 if category == "protein and antibody labeling kits"
replace tier2 = 1 if category == "protein gel stains"
replace tier2 = 1 if category == "protein modifying enzymes"
replace tier2 = 1 if category == "pvdf blotting membranes"
replace tier2 = 1 if category == "qpcr beads"
replace tier2 = 1 if category == "qrt-pcr titration kit"
replace tier2 = 1 if category == "quantum dots"
replace tier2 = 1 if category == "radiolabeled nucleotides"
replace tier2 = 1 if category == "rapid dna ligation kits"
replace tier2 = 1 if category == "restriction enzyme buffers"
replace tier2 = 1 if category == "restriction enzymes"
replace tier2 = 1 if category == "reverse transcriptase"
replace tier2 = 1 if category == "rna extraction reagents"
replace tier2 = 1 if category == "rna polymerases"
replace tier2 = 1 if category == "rna stabilization reagent"
replace tier2 = 1 if category == "rnase"
replace tier2 = 1 if category == "rnase inhibitors"
replace tier2 = 1 if category == "rt-pcr systems"
replace tier2 = 1 if category == "seamless cloning kits"
replace tier2 = 1 if category == "silica bead based gel purification kit"
replace tier2 = 1 if category == "site-directed mutagenesis systems"
replace tier2 = 1 if category == "spin columns"
replace tier2 = 1 if category == "streptavidin conjugates"
replace tier2 = 1 if category == "ta cloning kits"
replace tier2 = 1 if category == "taq buffers"
replace tier2 = 1 if category == "taq dna ligases"
replace tier2 = 1 if category == "taq polymerases"
replace tier2 = 1 if category == "tissue pcr systems"
replace tier2 = 1 if category == "topo ta cloning kits"
replace tier2 = 1 if category == "protein quantitation assay kits"
replace tier2 = 1 if category == "transfection reagents"
replace tier2 = 1 if category == "transfection reagents - cellfectin (insect cell)"
replace tier2 = 1 if category == "transfection reagents - electroporation kits"
replace tier2 = 1 if category == "transfection reagents - electroporation reagent"
replace tier2 = 1 if category == "transfection reagents - in vivo delivery reagents"
replace tier2 = 1 if category == "transfection reagents - lentiviral packaging kits"
replace tier2 = 1 if category == "transfection reagents - other"
replace tier2 = 1 if category == "transfection reagents - polybrene (viral transduction)"
replace tier2 = 1 if category == "transfection reagents - protein transfection reagents"
replace tier2 = 1 if category == "unstained dna ladders"
replace tier2 = 1 if category == "unstained protein molecular-weight ladder"
replace tier2 = 1 if category == "unstained rna ladders"
replace tier2 = 1 if category == "vertical electrophoresis systems"
replace tier2 = 1 if category == "western blot blockers"
replace tier2 = 1 if category == "western blot boxes"
replace tier2 = 1 if category == "western blot enhancers"
replace tier2 = 1 if category == "western blot pen"
replace tier2 = 1 if category == "western blot rollers"
replace tier2 = 1 if category == "western blot stripping buffers"
replace tier2 = 1 if category == "western blot transfer buffers"
replace tier2 = 1 if category == "zero blunt topo cloning kits"

*---------------------------------------------------------------
* TIER 3: BUNDLED WITH DOCUMENTED OVERLAP MARKETS
*   CC supplements/buffers/dissociation (Gibco/HyClone ecosystem),
*   electrophoresis running buffers (system-specific for Tier 2 gels),
*   additional fluorophore sub-types (Molecular Probes line)
*---------------------------------------------------------------
replace tier3 = 1 if category == "cell culture dissociation reagents"
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
replace tier3 = 1 if category == "dulbecco's phosphate-buffered saline (dpbs) buffer"
replace tier3 = 1 if category == "fluorophore - calcium indicators"
replace tier3 = 1 if category == "fluorophore - cell tracer"
replace tier3 = 1 if category == "fluorophore - glutathione indicator"
replace tier3 = 1 if category == "fluorophore - lysosome indicators"
replace tier3 = 1 if category == "fluorophore - protein hydrophobicity"
replace tier3 = 1 if category == "fluorophore - ros indicators"
replace tier3 = 1 if category == "viability stains"
replace tier3 = 1 if category == "fluorophore - voltage indicators"
replace tier3 = 1 if category == "growth medium supplement"
replace tier3 = 1 if category == "hanks' balanced salt solution (hbss) buffer"
replace tier3 = 1 if category == "laemmli sample buffer"
replace tier3 = 1 if category == "lds sample buffer"
replace tier3 = 1 if category == "ligation reaction buffer"
replace tier3 = 1 if category == "mes-sds buffer"
replace tier3 = 1 if category == "mops-sds buffer"
replace tier3 = 1 if category == "native page running buffers"
replace tier3 = 1 if category == "native-page sample buffer"
replace tier3 = 1 if category == "phosphate-buffered saline (pbs) buffer"
replace tier3 = 1 if category == "reaction buffers"
replace tier3 = 1 if category == "reducing agents - bme"
replace tier3 = 1 if category == "tbe buffer"
replace tier3 = 1 if category == "tris-aceate-sds running buffer"
replace tier3 = 1 if category == "tris-acetate-edta (tae) buffer"
replace tier3 = 1 if category == "tris-glycine buffer"
replace tier3 = 1 if category == "tris-glycine-sds (tgs) buffer"
replace tier3 = 1 if category == "tris-tricine-sds buffer"

*---------------------------------------------------------------
* MASTER TREATMENT VARIABLES
*---------------------------------------------------------------
gen treated_strict  = (tier1 == 1)
gen treated_1and2   = (tier1 == 1 | tier2 == 1)
gen treated     = (tier1 == 1 | tier2 == 1 | tier3 == 1)

tab tier1
tab tier2
tab tier3
tab treated
    gen keep  = (support >= 20 & precision >= 0.8 & recall >= 0.8) //| (inrange(support, 10, 25) & precision >= 0.9 & recall >=0.90) 
    save ../output/categories_`embed', replace
end
main
