"""PDF page text to paragraphs, and what counts as a release heading. Both came
out of reading R's own manuals: the R FAQ was flagged as a changelog because
"2.1 What is R?" looked like a version, and R-intro's running page headers,
contents lines, code prompts, and lead-in lines were taken for section headings."""

from dragonfarm import documents as D


def test_numbered_section_titles_are_not_versions():
    for s in ["2.1 What is R?", "2.5.1 How can R be installed (Unix-like)", "5.10 Frequency tables from factors",
              "1.1 Imports", "Chapter 1: Introduction", "Install", ""]:
        assert not D.version_heading(s), s


def test_release_headings_are_versions():
    for s in ["0.3.4", "1.2", "v1.2.0", "Version 1.2 highlights", "dragonfarm 0.3.4", "pkg 0.3.4 (2026-01-01)",
              "0.3.4 Bug fixes", "(development version)", "2026-01-01 release", "1.0.0"]:
        assert D.version_heading(s), s


def test_a_faq_with_numbered_sections_is_not_a_changelog():
    faq = [{"section": s} for s in ["2.1 What is R?", "2.2 What machines does R run on?", "2.3 What is the current version of R?",
                                     "3.1 What is S?", "3.2 What is S-PLUS?"]]
    assert not D.changelog_like("R-FAQ.html", faq)
    news = [{"section": s} for s in ["0.3.4", "0.3.3", "0.3.2", "Intro"]]
    assert D.changelog_like("whatever.md", news)


def _pages():
    header = "Chapter 2: Simple manipulations; numbers and vectors"
    return [
        "\n".join(["Table of Contents", "1.1 Imports . . . . . 3", "2.6 Character vectors . . . . 12", "ii"]),
        "\n".join([header + " 8", "", "2.6 Character vectors", "Character quantities and character vectors are used",
                   "frequently in R, for example as plot labels. They are", "8"]),
        "\n".join([header + " 9", "printed using double quotes.", "", "A call such as", "> labs <- paste(c(\"X\",\"Y\"), 1:10, sep=\"\")",
                   "makes labs into a character vector.", "9"]),
        "\n".join([header + " 10", "has the same effect as", "the previous call.", "", "2.7 Index vectors",
                   "Subsets of the elements of a vector may be selected.", "", "An object may still have a mode. For example",
                   "the empty vector has mode logical.", "10"]),
    ]


def test_running_headers_page_numbers_and_contents_lines_are_dropped():
    text = D.pages_to_text(_pages())
    assert "Chapter 2:" not in text
    assert "Table of Contents" not in text and "1.1 Imports" not in text
    assert "\nii\n" not in text and "\n8\n" not in text


def test_real_headings_survive_and_code_or_fragments_do_not():
    text = D.pages_to_text(_pages())
    headings = [l for l in text.split("\n\n") if l.startswith("## ")]
    assert "## 2.6 Character vectors" in headings
    assert "## 2.7 Index vectors" in headings
    assert len(headings) == 2, headings
    assert "A call such as > labs" in text          # the lead-in stays with its example


def test_sentences_broken_across_pages_are_rejoined():
    text = D.pages_to_text(_pages())
    assert "plot labels. They are printed using double quotes." in text


def test_short_documents_keep_their_edge_lines():
    # Under three pages there is no notion of a running header: nothing is dropped.
    one = D.pages_to_text(["Returns policy", "Items may be returned within 30 days.", "Page 1"])
    assert "Items may be returned within 30 days." in one


def test_a_paragraph_starting_with_hashes_is_not_a_heading():
    text = "## Setup\n\nInstall it.\n\n## first evaluation in S S> cube(2) " + "Error in sq(): Object n not found " * 20 + "\n\nMore text."
    chunks = D.chunk_text(text, "manual.pdf", max_words=170, min_words=5)
    assert all(c["section"] == "Setup" for c in chunks), [c["section"] for c in chunks]


def test_html_heading_anchor_glyphs_are_stripped():
    html = "<html><body><h2>2.8 Citing R ¶</h2><p>Use citation().</p><h3>Setup #</h3><p>Install.</p><h2>Links Permalink to this heading</h2><p>x</p></body></html>"
    text = D.html_to_text(html)
    assert "## 2.8 Citing R\n" in text + "\n"
    assert "### Setup\n" in text + "\n"
    assert "## Links\n" in text + "\n"
    assert "¶" not in text and "Permalink" not in text


def test_fragmented_extraction_is_detected_and_layout_text_tidied():
    frag = "De\nce\nmb\ner\n11,\n202\n4\n" * 4
    assert D.fragmented(frag)
    assert not D.fragmented("December 11, 2024\n\nDear Costco Shareholders,\n")
    assert not D.fragmented("a\nb\nc")          # too short to judge
    tidy = D.tidy_layout("December    11,  2024   \n\nDear  Costco   Shareholders,\n")
    assert tidy == "December 11, 2024\n\nDear Costco Shareholders,"


def test_single_short_words_are_not_headings():
    pages = ["\n".join(["In", "fiscal 2024 we opened 29 warehouses.", "", "Mr", "Jelinek retired.", "",
                        "Dear Costco Shareholders", "The merchandise we sell is the lifeblood of the business."])]
    text = D.pages_to_text(pages)
    headings = [l for l in text.split("\n\n") if l.startswith("## ")]
    assert headings == ["## Dear Costco Shareholders"], headings


def test_pdf_chunks_record_the_page_they_start_on():
    pages = ["## Letter\n\n" + "Sales grew five percent this year. " * 30,
             "## Results\n\n" + "Net income rose seventeen percent. " * 30,
             "Membership fees were 4.8 billion dollars. " * 10]
    chunks = D.chunk_text(D.pages_to_text(pages), "report.pdf", max_words=170, min_words=20)
    assert all("\x01" not in c["text"] for c in chunks)
    pages_seen = [c.get("page") for c in chunks]
    assert pages_seen[0] == 1 and 2 in pages_seen and pages_seen == sorted(pages_seen)
    assert {c["section"] for c in chunks if c.get("page") == 2} == {"Results"}


def test_single_page_and_non_pdf_text_has_no_page():
    chunks = D.chunk_text("## A\n\n" + "word " * 50, "notes.md", min_words=10)
    assert all("page" not in c for c in chunks)


def test_dot_leader_contents_entries_are_dropped_but_table_rows_kept():
    page = "\n".join([
        "PART I",
        "Item 1. Business . . .. . .. .. . .. . .. . .. .. . .. . 4",
        "Item 1A. Risk Factors . . .. .. . .. . .. . .. .. . .. . 10",
        "Net cash used in investing activities . . . . . . . . (4,409) (4,972)",
        "Total short-term investments . . . . . . . . $ 689 $ (1) $ 688",
        "Certificates of deposit . . . . . . . . . . 550 — 550",
    ])
    text = D.pages_to_text([page, "filler line one.", "filler line two."])
    assert "Item 1. Business" not in text and "Risk Factors" not in text
    assert "(4,409) (4,972)" in text
    assert "$ 689 $ (1) $ 688" in text
    assert "550 — 550" in text


def test_lost_apostrophes_are_restored():
    assert D.LOST_APOSTROPHE.sub("\u2019", "Registrant\ufffds Common Equity; Costco\ufffds; don\ufffdt; M\ufffdxico") == \
        "Registrant\u2019s Common Equity; Costco\u2019s; don\u2019t; M\ufffdxico"


def test_unit_notes_carry_into_later_money_chunks():
    text = "\n\n".join([
        "## Item 7",
        "(dollars in millions, except per share data)",
        "Net sales increased five percent in the year. " * 8,
        "## Liquidity",
        "Net cash provided by operating activities totaled $11,339 in 2024, compared to $11,068 in 2023. " * 4,
        "## People",
        "We employed 333,000 employees worldwide at the end of the year and paid them well. " * 4,
        "## Letter",
        "Net sales were $249.6 billion this year, an increase of five percent over last year. " * 4,
    ])
    chunks = {c["section"]: c["text"] for c in D.chunk_text(text, "10k.pdf", min_words=20)}
    assert chunks["Liquidity"].startswith("[dollars in millions, except per share data]")
    assert not chunks["People"].startswith("[")          # no money, no note
    assert not chunks["Letter"].startswith("[")          # says "billion" itself
    assert D.UNIT_NOTE.search("(amounts in millions, except par value and share data)")
    assert not D.UNIT_NOTE.search("(see Note 4)")


def test_unit_note_headings_set_the_unit_and_keep_the_section():
    text = "\n\n".join([
        "## Note 4—Debt",
        "## (amounts in millions)",
        "The carrying value of long-term debt was $5,794 and $6,084 at year end. " * 4,
    ])
    chunks = D.chunk_text(text, "10k.docx", min_words=20)
    assert {c["section"] for c in chunks} == {"Note 4—Debt"}
    assert chunks[0]["text"].startswith("[amounts in millions]")


def test_dot_leaders_are_recognised_but_an_ellipsis_is_not():
    assert D.DOT_LEADER.sub(" ", "Net sales . . . . . . 249,625").split() == ["Net", "sales", "249,625"]
    assert D.DOT_LEADER.sub(" ", "and so on...") == "and so on..."


def test_a_unit_note_in_front_of_a_heading_is_split_off():
    text = "## (amounts in millions, except share data) Note 1—Summary of Significant Accounting Policies\n\n" + \
           "Cash equivalents were $9,906 at year end and are carried at cost. " * 4
    chunks = D.chunk_text(text, "10k.docx", min_words=20)
    assert chunks[0]["section"] == "Note 1—Summary of Significant Accounting Policies"
    assert chunks[0]["text"].startswith("[amounts in millions, except share data]")


def test_emphasised_paragraphs_become_headings_only_before_prose():
    try:
        import docx
    except ImportError:
        return
    import tempfile, os
    d = docx.Document()
    p = d.add_paragraph(); p.add_run("Description of Business").italic = True
    d.add_paragraph("Costco Wholesale Corporation operates membership warehouses and e-commerce sites in several countries.")
    p = d.add_paragraph(); p.add_run("Recorded Basis").bold = True
    d.add_paragraph("1,234")
    p = d.add_paragraph(); p.add_run("2024	2023").bold = True
    d.add_paragraph("Net sales grew in every segment and every region during the year that ended in September.")
    p = d.add_paragraph(); p.add_run("This sentence is bold but it is prose.").bold = True
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "t.docx")
        d.save(path)
        text = D.read_docx(path)
    assert "### Description of Business" in text
    assert "### Recorded Basis" not in text and "Recorded Basis" in text
    assert "### 2024" not in text
    assert "### This sentence" not in text


def test_link_lists_without_nav_tags_are_dropped():
    html = ("<html><body><div class='sidebar'><p><a href='/'>Home</a> <a href='/d'>Download</a> "
            "<a href='/c'>CRAN</a> <a href='/a'>About R</a> <a href='/l'>Logo</a></p></div>"
            "<div role='navigation'><p>Skip me entirely please, this is navigation text.</p></div>"
            "<h2>Introduction to R</h2><p>R is a language and environment for statistical computing and "
            "graphics, see <a href='/s'>S</a> for history.</p></body></html>")
    text = D.html_to_text(html)
    assert "Download" not in text and "Skip me" not in text
    assert "R is a language and environment" in text and "see S for history" in text


def test_rows_of_numbers_are_not_headings():
    assert D.mostly_letters("2.3 Generating regular sequences")
    assert not D.mostly_letters("59.75 93.0 900 5 1.9 yes")
    page = "\n".join(["Price Floor Area Rooms Age Cent.heat", "", "59.75 93.0 900 5 1.9 yes",
                      "The data frame has one row per house and is read with read.table()."])
    text = D.pages_to_text([page])
    assert "## 59.75" not in text


def test_year_columns_are_labelled_under_a_year_header():
    lines = ["2024 2023 2022",
             "Net cash provided by operating activities ... ... $ 11,339 $ 11,068 $ 7,392",
             "Net cash used in investing activities . ... (4,409) (4,972) (3,915)",
             "Gross margin percentage . ... 10.92 % 10.57 % 10.48 %",
             "Dividend to noncontrolling interest — — (208)",
             "Net sales grew 5 percent in 2024 compared with 2023, driven by traffic.",
             "Membership fees .. ... 4,828 4,580"]
    out = D.label_year_columns(lines)
    assert out[1] == "Net cash provided by operating activities (2024: $11,339; 2023: $11,068; 2022: $7,392)"
    assert out[2] == "Net cash used in investing activities (2024: (4,409); 2023: (4,972); 2022: (3,915))"
    assert out[3] == "Gross margin percentage (2024: 10.92%; 2023: 10.57%; 2022: 10.48%)"
    assert out[4].startswith("Dividend to noncontrolling interest (2024: ")
    assert out[5] == lines[5] and out[6] == lines[6]          # prose and short rows untouched


def test_year_labels_stop_after_the_table():
    lines = ["2024 2023", "Revenue 10 9", "This paragraph is prose.", "More prose here.", "Still prose.",
             "Another row 5 4"]
    out = D.label_year_columns(lines)
    assert out[1] == "Revenue (2024: 10; 2023: 9)"
    assert out[5] == "Another row 5 4"


def test_word_tables_collapse_merged_cells_and_label_years():
    try:
        import docx
    except ImportError:
        return
    d = docx.Document()
    t = d.add_table(rows=4, cols=4)
    t.cell(0, 1).text = "September 1, 2024"; t.cell(0, 2).text = "September 3, 2023"; t.cell(0, 3).text = "August 28, 2022"
    t.cell(1, 0).merge(t.cell(1, 3)).text = "REVENUE"
    for k, v in enumerate(["Net sales", "$ 249,625", "$ 237,710", "$ 222,730"]):
        t.cell(2, k).text = v
    for k, v in enumerate(["Dividend", "—", "—", "(208)"]):
        t.cell(3, k).text = v
    rows = D.docx_table_rows(t)
    assert rows[0] == "September 1, 2024 | September 3, 2023 | August 28, 2022"
    assert rows[1] == "REVENUE"                                   # merged across four columns, once
    assert rows[2] == "Net sales (2024: $249,625; 2023: $237,710; 2022: $222,730)"
    assert rows[3] == "Dividend (2024: —; 2023: —; 2022: (208))"  # equal neighbours are kept


def test_a_capitalised_title_starts_a_section_even_after_an_unfinished_page():
    pages = ["Report of the auditors, signed in Seattle, Washington October 8, 2024",
             "\n".join(["COSTCO WHOLESALE CORPORATION", "CONSOLIDATED STATEMENTS OF INCOME",
                        "52 Weeks Ended 53 Weeks Ended 52 Weeks Ended", "2024 2023 2022",
                        "Net sales ... $ 249,625 $ 237,710 $ 222,730",
                        "Revenue is recognised when goods are delivered to members in the warehouse."]),
             "filler text for a third page."]
    text = D.pages_to_text(pages)
    headings = [l for l in text.split("\n\n") if l.startswith("## ")]
    assert "## CONSOLIDATED STATEMENTS OF INCOME" in headings
    assert not any("Weeks Ended" in h for h in headings)
    assert D.repetitive("52 Weeks Ended 53 Weeks Ended 52 Weeks Ended")
    assert not D.repetitive("Opinion on the Consolidated Financial Statements")
    assert D.all_caps_title("CONSOLIDATED STATEMENTS OF INCOME") and not D.all_caps_title("Net sales")


def test_lists_printed_a_line_each_keep_their_entries_apart():
    from dragonfarm.documents import join_lines, pages_to_text
    text = pages_to_text(["Locations\nALABAMA \u2013 5\nALASKA \u2013 5\nCALIFORNIA \u2013 140\nNEW YORK \u2013 19"])
    assert "ALABAMA \u2013 5; ALASKA \u2013 5; CALIFORNIA \u2013 140; NEW YORK \u2013 19" in text
    # ordinary wrapped lines still join with a space
    assert join_lines(["The total is", "897 locations \u2013 5 new."]) == "The total is 897 locations \u2013 5 new."
    assert join_lines(["Item 1 \u2013 Business", "continued text"]) == "Item 1 \u2013 Business continued text"


def test_no_break_spaces_from_pdfs_become_spaces(monkeypatch=None):
    import types, sys
    from dragonfarm import documents as Dm

    class Page:
        def extract_text(self, **kw):
            return "Locations\nCALIFORNIA\u00a0\u2013\u00a0140\nCOLORADO\u00a0\u2013\u00a016"

    fake = types.SimpleNamespace(PdfReader=lambda fh: types.SimpleNamespace(pages=[Page()]))
    old = Dm._need
    Dm._need = lambda *a, **k: fake
    try:
        text = Dm.pdf_to_text(None)
    finally:
        Dm._need = old
    assert "\u00a0" not in text
    assert "CALIFORNIA \u2013 140; COLORADO \u2013 16" in text


def test_a_numbered_heading_after_a_finished_sentence_starts_a_section():
    from dragonfarm.documents import pages_to_text
    page = ("This is a long line of text that goes on for quite a while and ends with a full stop at the end.\n"
            "6.4 Updating packages\n"
            "The command update.packages() is the simplest way to update.\n"
            "It grew in a long sentence that keeps going and going without stopping here as\n"
            "2.5 Million users joined in the year")
    text = pages_to_text([page])
    assert "## 6.4 Updating packages" in text
    assert "## 2.5" not in text               # the middle of an unfinished sentence, not a heading


def test_outline_headings_start_sections_and_addresses_never_do():
    # Cover page and body of an FDA guidance: the agency's address used to be
    # the section of every chunk, and "I. INTRODUCTION" was read as a sentence.
    from dragonfarm.documents import pages_to_text
    page = ("10001 New Hampshire Ave., Hillandale Bldg., 4th Floor\n"
            "Silver Spring, MD 20993-0002\n"
            "\n"
            "I. INTRODUCTION\n"
            "This guidance describes current recommendations for covariates.\n"
            "\n"
            "III. ESTIMANDS (A.3)\n"
            "An estimand is a precise description of the treatment effect.\n"
            "\n"
            "A. General Considerations\n"
            "Sponsors can adjust for baseline covariates.\n"
            "\n"
            "A. Smith wrote this. It is a sentence, not a title\n")
    text = pages_to_text([page])
    assert "## 10001" not in text
    assert "## I. INTRODUCTION" in text
    assert "## III. ESTIMANDS (A.3)" in text
    assert "## A. General Considerations" in text
    assert "## A. Smith" not in text


def test_address_lines_are_recognised():
    from dragonfarm.documents import ADDRESS_LINE
    for s in ["10001 New Hampshire Ave., Hillandale Bldg., 4th Floor", "1600 Pennsylvania Avenue",
              "221 Baker Street", "Acme Corp, Suite 400"]:
        assert ADDRESS_LINE.search(s), s
    for s in ["1 Introduction", "2.5 Model selection", "10 Ways to Fit a Model", "I. INTRODUCTION"]:
        assert not ADDRESS_LINE.search(s), s
