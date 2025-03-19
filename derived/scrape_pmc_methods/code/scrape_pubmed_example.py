from Bio import Entrez

Entrez.email = "your_email@example.com"

def get_pmcid(pmid):
    """Convert a PubMed ID to a PMCID using Entrez.elink."""
    handle = Entrez.elink(dbfrom="pubmed", db="pmc", id=pmid)
    records = Entrez.read(handle)
    handle.close()
    try:
        pmcid = records[0]["LinkSetDb"][0]["Link"][0]["Id"]
        return "PMC" + pmcid  # PMCID is typically prefixed with 'PMC'
    except (IndexError, KeyError):
        return None

# Example PubMed ID
pmid = "33016909"
pmcid = get_pmcid(pmid)

if pmcid:
    print(f"PMCID for PMID {pmid} is {pmcid}")
    # Fetch full-text XML from the PMC database
    handle = Entrez.efetch(db="pmc", id=pmcid, rettype="xml", retmode="text")
    xml_data = handle.read()
    handle.close()
    with open("pmc_record.xml", "w", encoding="utf-8") as f:
        f.write(xml_data.decode("utf-8"))
    print("Full-text XML downloaded from PMC.")
else:
    print("No PMCID found for this PMID; the full text may not be available in PMC.")
