# Map dataset columns to prompt, response, and system text

Each argument is either a column name or a
[`glue::glue()`](https://glue.tidyverse.org/reference/glue.html)
template that combines several columns, such as `"{subject}\n\n{body}"`.
Templates are rendered per row when the training files are written.

## Usage

``` r
dragon_map(dataset, prompt, response, system = NULL)
```

## Arguments

- dataset:

  A `dragon_dataset`.

- prompt:

  Column name or template for the user turn.

- response:

  Column name or template for the assistant turn.

- system:

  Optional column name or template for the system prompt. A template
  with no braces and no matching column is used as a constant system
  prompt for every row.

## Value

The dataset with the mapping attached.

## Examples

``` r
ds <- dragon_dataset(dragon_example_data())
ds <- dragon_map(ds, prompt = "{subject}\n\n{body}", response = "reply")
dragon_preview(ds, n = 1)
#> 
#> ── Row 1 
#> user:
#> Breeze air purifier keeps dropping off Wi-Fi
#> 
#> My Breeze air purifier connects fine for a few hours and then drops off the network. I have to power cycle it to get it back. Router is a fairly new mesh system.
#> assistant:
#> Thanks for the details. Wi-Fi drops on the Breeze air purifier are almost always a 2.4 GHz band-steering issue with mesh routers. Please try these steps: (1) In your router app, create a dedicated 2.4 GHz network or temporarily disable band steering. (2) Hold the reset button on the Breeze air purifier for 10 seconds until the light blinks amber. (3) Set it up again in the app on that 2.4 GHz network. If it still drops after 24 hours, reply with your router model and we will escalate to our network team.
```
