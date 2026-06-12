import sys
import xml.etree.ElementTree as ET

def text(elem, tag):
    child = elem.find(tag)
    return child.text.replace("\t", " ").replace("\n", " ").strip() if (child is not None and child.text) else ""

out = sys.stdout.write
try:
    tree = ET.parse(sys.stdin)
except ET.ParseError as e:
    sys.stderr.write(f"parse_grants.py: XML parse error: {e}\n")
    sys.exit(1)

root = tree.getroot()
for art in root.iter("PubmedArticle"):
    pmid_el = art.find("./MedlineCitation/PMID")
    if pmid_el is None or not pmid_el.text:
        continue
    pmid = pmid_el.text.strip()
    grants = art.findall("./MedlineCitation/Article/GrantList/Grant")
    for g in grants:
        out("\t".join([
            pmid,
            text(g, "GrantID"),
            text(g, "Acronym"),
            text(g, "Agency"),
            text(g, "Country"),
        ]) + "\n")
