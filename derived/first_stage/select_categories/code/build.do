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
*   May 4, 2026 (v5f) — End-user mag bead correction. Re-read EU paras 219-228:
*     paragraph 226 defines the affected market as "polymer-based magnetic beads
*     to OEM customers" specifically; paragraph 228 explicitly clears end-user
*     particles ("does not give rise to serious doubts under any plausible market
*     definition"). Para 220 documents that OEM and end-user channels are
*     manufactured at different facilities (e.g. Miltenyi) with different prices,
*     margins, and contract terms (paras 222-224). The two are SEPARATE markets,
*     not bundled tiers of one. End-user mag beads do not satisfy the strict
*     bundling criterion for Tier 3.
*     Removed 25 end-user mag bead categories from T3 -> control:
*       - 14 affinity resins (magnetic) — Dynabeads, Pierce mag beads, etc. (the
*         beads themselves, sold to academic researchers, not OEM customers)
*       - magnetic beads - other, magnetic cell separation kits, magnetic ip kit
*       - immunomagnetic cell separation beads/columns (Miltenyi MACS, end-user)
*       - 6 instrument/instrument part magnetic separator categories (DynaMag,
*         MiniMACS, magnetic plates, separation stands — the hardware that holds
*         the beads, all end-user)
*     KEPT in Tier 2: magnetic bead-based purification/selection KITS — these are
*     NA purification kits (para 11(v) serious-doubts market), distinct from
*     end-user mag beads.
*     Net: 373 product rows shift T3 -> control. Treated share: 4.60% -> 4.43%.
*
*   May 4, 2026 (v5e) — Reverse-direction audit: ran the same paragraph-citation
*     rules against ALL 1,971 control categories. Found 48 candidates by name
*     keyword match, then product-sample audit confirmed 38 are correctly control
*     (false-positive keyword matches: histology mounting media, density gradient
*     media, IHC blocking sera, empty bottles, generic chemistry). 5 genuine
*     misclassifications corrected:
*       - yeast transformation kit                     -> T2 (cloning, para 12(vi))
*       - precipitation-based dna purification kits    -> T2 (NA purif, para 11(v))
*       - precipitation-based rna purification kits    -> T2 (NA purif, para 11(v))
*       - instrument - dynabead magnets                -> T3 (end-user mag bead)
*       - instrument part - magnetic plate             -> T3 (end-user mag bead)
*     Total impact: +18 product rows treated. Treated share moves 4.59% -> 4.60%.
*
*   May 4, 2026 (v5d) — Strict Tier 3 audit. Applied two rules:
*     (a) Para 126 buffer exclusion: 18 buffer/loading-dye categories removed
*         (laemmli, lds, mes-sds, mops-sds, tris-glycine variants, tbe, tae,
*         loading dyes, gel tracking dyes, qpcr ROX, WB transfer buffer, BME).
*         Same rule that put sirna buffers / t4 ligase buffers in control.
*     (b) "Cell culture supplements" prefix misnomer: 5 categories (peptone,
*         tryptone, yeast extract, casamino acids, sugars) are actually
*         bacterial/yeast culture ingredients, not mammalian cell-culture-
*         media bundles. Para 41 covers cell culture media, not LB media.
*     Net: 25 categories removed from Tier 3 (615 product rows shifted to
*     control). Remaining 40 Tier 3 entries are direct mag-bead end-user
*     analogs, mammalian cell culture supplements, and NA workflow bundles.
*
*   May 4, 2026 (v5c) — Systematic rule-based audit of every treated entry
*     against EU/FTC text. Three corrections:
*       - sirna buffers: T1 -> control (para 126 excludes buffers)
*       - sirna transfection medium: T1 -> T2 (para 122 cleared transfection;
*         divested-but-not-serious-doubts pattern)
*       - sirna transfection reagents: T1 -> T2 (same)
*       - gene-specific rnai reagents: T2 -> control (data is Drosophila
*         academic RNAi + Sigma shRNA + CRISPR, none are EU siRNA market)
*     Tier 1 now has exactly the 5 EU serious-doubts buckets:
*       (1) cell culture media (para 41), (2) FBS (para 69),
*       (3) siRNA effectors (para 98), (4) miRNA effectors (para 105 — no
*       categories surface in the data), (5) OEM polymer mag beads (para 278
*       — Sera-Mag not in academic data).
*     Total T1: 20 categories.
*
*   May 3, 2026 (v5) — Adapted for post-cleaning category names. The category
*     cleaning pipeline (0_clean_category_file.py) applies these transforms before
*     build.do runs:
*       - Unicode normalize: en-dash (U+2013), em-dash, smart quotes, ellipsis -> ASCII
*       - Lowercase, strip whitespace
*       - Apply ~50 known typo corrections (nuclease enyzmes, reverse transcriptiase,
*         instrument - sequencerr, rmpi, etc.)
*       - Auto-collapse singular/plural pairs (incl. medium->media)
*       - Collapse antibody categories: *primary*polyclonal* -> "polyclonal primary antibodies",
*         *primary*monoclonal* -> "monoclonal primary antibodies", *secondary* -> "secondary antibodies"
*       - Collapse all *pipette tip* -> "pipette tips"
*       - Collapse all *elisa* -> "elisa kits"
*     Implications for this file:
*       - Use post-cleaning canonical strings (no typos, hyphens not en-dashes, plural form)
*       - Antibody host-specific categories don't survive — strict reading: control
*         (would only matter if EU named a specific host antibody, which it didn't)
*
*   May 3, 2026 — Exhaustive control-list audit additions:
*     - Tier 2 additions:
*         reverse transcriptiase (typo of existing entry)
*         2d gel sample prep kits, pre-cast ief gels (SDS-PAGE/IEF)
*         (corrected: t4 ligase buffers + qpcr beads remain control per EU para 126
*          which excludes buffers/ancillary reagents from affected markets)
*     - Tier 3 additions:
*         gel/dna/rna loading dyes and buffers, gel tracking dyes (electrophoresis bundling)
*         qpcr reaction dyes (qPCR bundling)
*         instrument - magnetic separators / separation stand / etc. (end-user mag bead hw)
*
*   Apr 30, 2026 — Product-level audit additions/fixes:
*     - Bug fix: magnetic bead–based mrna selection kit (en dash, was silent NULL match)
*     - Added: tris-buffered saline (tbs) buffer  -> Tier 2 (process liquid)
*     - Added: specialty polymerase             -> Tier 2 (EU para 11(iv))
*     - Added: nuclease enyzmes (typo variant)  -> Tier 2
*     - Added: dna ligation mix                 -> Tier 2 (cloning kit)
*     - Added: column-based rna purification kit -> Tier 2 (singular variant)
*     - Added: ddpcr systems                    -> Tier 2 (PCR kit variant)
*     - Moved: spin columns                     -> Tier 3 (generic plasticware)
*
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
* sirna buffers moved to CONTROL (para 126: buffers/ancillary excluded)
* sirna transfection medium and reagents moved to TIER 2 below
*   (para 122 cleared transfection without serious doubts; FTC physically
*    divested DharmaFECT, so this is the "divested-but-not-serious-doubts"
*    pattern — same as PBS/process liquids and shRNA)

* --- miRNA: no exact "synthetic mirna" category in current data; FTC def. U
*     includes microRNA. (gene-specific rnai reagents is ambiguous -> Tier 2)

count if tier1 == 1
assert inrange(r(N), 18, 24)  // expected 20 after v5c (sirna buffers/transfection moved out of T1)

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

* --- Process liquids (EU para 27: separate product market; FTC HyClone
*     divestiture covers them but EU did not analyze for serious doubts) ---
replace tier2 = 1 if category == "phosphate-buffered saline (pbs) buffer"
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
* siRNA-specific transfection — divested as part of FTC Dharmacon Gene Modulation
* Business (Definition U includes DharmaFECT). EU para 122 cleared transfection
* without serious doubts; placement is "divested-but-not-serious-doubts" pattern.
replace tier2 = 1 if category == "sirna transfection medium"
replace tier2 = 1 if category == "sirna transfection reagents"
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
replace tier2 = 1 if category == "magnetic bead-based mrna selection kit"  // post-cleaning: en-dash normalized to hyphen
replace tier2 = 1 if category == "rna extraction reagents"
replace tier2 = 1 if category == "rna stabilization reagent"
replace tier2 = 1 if category == "silica bead based gel purification kit"
* spin columns moved from Tier 2 -> Tier 3 (generic plasticware, not finished NA kit)

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


* --- Additional categories surfaced by product-level audit (Apr 30, 2026) ---
* TBS buffer (process liquid, EU para 27 separate market)
replace tier2 = 1 if category == "tris-buffered saline (tbs) buffer"
* Other specialty polymerase (EU para 11(iv) explicitly named market)
replace tier2 = 1 if category == "specialty polymerase"
* (Note: typo variant "nuclease enyzmes" cleaning-pipeline-collapses into "nuclease enzymes" already in Tier 2)
* Cloning kit format
replace tier2 = 1 if category == "dna ligation mix"
* (Note: singular "column-based rna purification kit" cleaning-pipeline-collapses into "column-based rna purification kits" already in Tier 2)
* PCR variant (EU para 135 ready-to-use kit territory; ddPCR not enumerated but is a master-mix kit)
replace tier2 = 1 if category == "ddpcr systems"


* --- Additional categories surfaced by exhaustive control-list audit (May 3, 2026) ---
* (Note: typo variant "reverse transcriptiase" cleaning-pipeline-collapses into "reverse transcriptase" already in Tier 2)
* 2D gel sample prep — SDS-PAGE workflow (EU 12(viii))
replace tier2 = 1 if category == "2d gel sample prep kits"
* Isoelectric focusing pre-cast gels — same SDS-PAGE/electrophoresis market
replace tier2 = 1 if category == "pre-cast ief gels"
* (Earlier draft proposed t4 dna/rna ligase buffer and qpcr beads here, but
*  EU para 126 excludes "buffers, dNTPs and other ancillary reagents" from
*  the affected market analysis. Defensive check below verifies they stay control.)


* --- May 4 reverse-direction control audit additions ---
* Yeast cloning kit (EU para 12(vi) cloning)
replace tier2 = 1 if category == "yeast transformation kit"
* Precipitation-based NA purification kit formats (EU para 11(v))
replace tier2 = 1 if category == "precipitation-based dna genomic purification kits"
replace tier2 = 1 if category == "precipitation-based rna purification kits"

count if tier2 == 1
assert inrange(r(N), 138, 162)  // expected ~156 after v5e

*-------------------------------------------------------------------------------
* TIER 3: BUNDLING / EXTENSION ROBUSTNESS
*-------------------------------------------------------------------------------

* --- Cell culture supplements (bundled with HyClone media) ---
replace tier3 = 1 if category == "cell culture nutritional supplements - amino acids"
replace tier3 = 1 if category == "cell culture nutritional supplements - b27"
replace tier3 = 1 if category == "cell culture nutritional supplements - glucose"
replace tier3 = 1 if category == "cell culture nutritional supplements - insulin"
replace tier3 = 1 if category == "cell culture nutritional supplements - its-g"
replace tier3 = 1 if category == "cell culture nutritional supplements - l-glutamine"
replace tier3 = 1 if category == "cell culture nutritional supplements - lif"
replace tier3 = 1 if category == "cell culture nutritional supplements - other"
replace tier3 = 1 if category == "cell culture nutritional supplements - sodium pyruvate"
replace tier3 = 1 if category == "cell culture nutritional supplements - vitamins"
replace tier3 = 1 if category == "cell culture dissociation reagents"
replace tier3 = 1 if category == "growth medium supplement"

* --- End-user magnetic beads (NOT in EU OEM divestiture; bundling robustness) ---

* --- Generic NA purification consumables (moved from Tier 2 — empty plasticware,
*     not finished kits) ---
replace tier3 = 1 if category == "spin columns"

* --- Electrophoresis sample/running buffers (bundled with Tier 2 SDS-PAGE) ---

* --- Western blot membrane-adjacent consumables (papers and transfer buffers
*     are pre-/at-transfer; EU para 309 transfer-step overlap) ---
replace tier3 = 1 if category == "gel blotting papers"

* --- IVT specialty kits (cloning workflow extension) ---
replace tier3 = 1 if category == "capped mrna synthesis kits"
replace tier3 = 1 if category == "in vitro transcription kit"
replace tier3 = 1 if category == "direct pcr lysis reagents"


* --- Electrophoresis loading reagents and tracking dyes (bundling to SDS-PAGE/agarose) ---
*     Identified by exhaustive product-level audit, May 3 2026.

* --- qPCR passive reference dyes (bundling to qPCR systems, EU para 135) ---

* --- End-user mag bead instruments (Miltenyi MiniMACS etc., NOT EU OEM bead) ---


* --- May 4 reverse-direction control audit T3 additions ---
* Invitrogen DynaMag — parallel to other instrument - magnetic separation entries

count if tier3 == 1
assert inrange(r(N), 12, 22)  // expected ~17 after v5f (end-user mag beads -> control)

*-------------------------------------------------------------------------------
* DEFENSIVE CHECKS — categories explicitly EXCLUDED from treatment
*-------------------------------------------------------------------------------
foreach c in "synthetic crrna" "dntps" "taq buffers" ///
             "pre-designed qpcr assays" "custom-designed qpcr assays" ///
             "fluorophore - general" "fluorophore - nucleic acid stain" ///
             "nucleic acid gel stains" "streptavidin conjugates" "quantum dots" ///
             "modified nucleotides" "radiolabeled nucleotides" ///
             "protein quantitation assay kits" "phosphoprotein electrophoresis reagents" ///
             "nucleic acid quantitation" ///
             "nucleic acid modifying enzymes - creatine kinase (non-nucleic acid enzyme)" ///
             "nucleic acid modifying enzymes - t4 dna ligase buffer" ///
             "nucleic acid modifying enzymes - t4 polynucleotide kinase buffer" ///
             "nucleic acid modifying enzymes - t4 rna ligase buffer" ///
             "restriction enzyme buffers" "qpcr beads" "pcr barcoding expansion" ///
             "fluorophore - calcium indicators" "fluorophore - cell tracer" ///
             "fluorophore - glutathione indicator" "fluorophore - lysosome indicators" ///
             "fluorophore - protein hydrophobicity" "fluorophore - ros indicators" ///
             "fluorophore - voltage indicators" "viability stains" ///
             "western blot blockers" "western blot enhancers" "western blot pen" ///
             "western blot rollers" "western blot stripping buffers" ///
             "reaction buffers" "ligation reaction buffer" {
    count if category == "`c'" & (tier1 == 1 | tier2 == 1 | tier3 == 1)
    assert r(N) == 0
}

*-------------------------------------------------------------------------------
* MASTER TREATMENT VARIABLES
*-------------------------------------------------------------------------------
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

    gen keep = (support >= 20 & precision >= 0.8 & recall >= 0.8) //| (inrange(support, 10, 25) & precision >= 0.9 & recall >=0.90)
    save ../output/categories_`embed', replace
end
main
