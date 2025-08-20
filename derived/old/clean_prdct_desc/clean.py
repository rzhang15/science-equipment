import pandas as pd
import html
import re
from cleantext import clean

def full_clean(text):
    if not isinstance(text, str):
        return ""

    # Convert HTML entities (e.g., '&#946;') to Unicode characters (e.g., 'β')
    text = html.unescape(text)

    # Remove patterns like [???? ????????????]
    # This pattern removes any substring that starts with [ and ends with ]
    # and contains only question marks and whitespace.
    text = re.sub(r'\[[\?\s]+\]', '', text)

    # Remove patterns like #6Q8030796694-000050#
    # This pattern removes any substring that starts and ends with '#' (non-greedy)
    text = re.sub(r'#.*?#', '', text)

    # Clean the text using cleantext with desired options.
    cleaned = clean(
        text,
        clean_all=False,      # Execute only specified cleaning operations
        extra_spaces=True,    # Remove extra white spaces
        stemming=True,        # Stem the words
        stopwords=True,       # Remove stop words (in the specified language)
        lowercase=True,       # Convert text to lowercase
        numbers=False,        # Do not remove digits (keep them for chemical names)
        punct=False,          # Do not remove punctuation (preserve scientific notation)
        stp_lang='english'    # Language for stop words
    )

    return cleaned

# Load the Excel file
df = pd.read_excel("product_desc.xlsx")

# Ensure the column exists and fill missing values with an empty string
if "product_desc" not in df.columns:
    raise ValueError("Column 'product_desc' not found in the Excel file")
df["product_desc"] = df["product_desc"].fillna("")

# Apply the cleaning function to each product description
df["cleaned_product_desc"] = df["product_desc"].apply(full_clean)

# Save the cleaned data to a new Excel file
df.to_excel("cleaned_product_desc.xlsx", index=False)

print("Cleaned product descriptions have been saved to 'cleaned_product_desc.xlsx'.")
