# Check the Python environment and hardware

Prepares the Python environment if needed, then reports the interpreter,
library versions, the compute device that training will use, available
GPU memory, and whether a Hugging Face token is configured. Run this
first on a new machine.

## Usage

``` r
dragon_check()
```

## Value

Invisibly, a list of the collected facts.

## Examples

``` r
if (FALSE) { # \dontrun{
dragon_check()
} # }
```
