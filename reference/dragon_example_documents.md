# Example documents

Three short Markdown files of support policies for a fictional
smart-home company (returns and warranty; Wi-Fi, the app, and
automations; orders, billing, and support), about a thousand words in
all. They pair with
[`dragon_example_data()`](https://dragonfarm.dev/reference/dragon_example_data.md):
the example tickets are answered from these policies. Use them to try
[`dragon_documents()`](https://dragonfarm.dev/reference/dragon_documents.md),
[`dragon_ask()`](https://dragonfarm.dev/reference/dragon_ask.md), and
[`dragon_questions()`](https://dragonfarm.dev/reference/dragon_questions.md)
before bringing your own files.

## Usage

``` r
dragon_example_documents()
```

## Value

The directory containing the files.

## Examples

``` r
list.files(dragon_example_documents())
#> [1] "connectivity-and-app.md" "orders-and-support.md"  
#> [3] "returns-and-warranty.md"
if (interactive()) {
docs <- dragon_documents(dragon_example_documents(), name = "policies")
dragon_ask(docs, "How long is the return window?")
}
```
