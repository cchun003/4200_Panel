|term                                        |statistic |Tuition 1: Naive OLS |Tuition 2: Spatial RD |Tuition 3: Base DiDC |Tuition 4: Full DiDC |
|:-------------------------------------------|:---------|:--------------------|:---------------------|:--------------------|:--------------------|
|Tuition Gap LATE (S_i x Delta Tuition, $1k) |estimate  |-0.050**             |-0.031                |-0.020**             |-0.002               |
|Tuition Gap LATE (S_i x Delta Tuition, $1k) |std.error |(0.019)              |(0.022)               |(0.010)              |(0.014)              |
|Spatial Treatment (S_i)                     |estimate  |0.017                |-0.115*               |-0.107*              |0.011                |
|Spatial Treatment (S_i)                     |std.error |(0.068)              |(0.063)               |(0.055)              |(0.058)              |
|Tuition Gap (Delta Policy, $1k)             |estimate  |0.025                |0.039                 |                     |                     |
|Tuition Gap (Delta Policy, $1k)             |std.error |(0.026)              |(0.046)               |                     |                     |
|Effective Property Tax Rate                 |estimate  |                     |                      |                     |-21.384***           |
|Effective Property Tax Rate                 |std.error |                     |                      |                     |(3.118)              |
|State Income Tax Liability                  |estimate  |                     |                      |                     |0.000                |
|State Income Tax Liability                  |std.error |                     |                      |                     |(0.000)              |
|Federal Income Tax Liability                |estimate  |                     |                      |                     |0.000***             |
|Federal Income Tax Liability                |std.error |                     |                      |                     |(0.000)              |
|Log Real GDP Per Capita                     |estimate  |                     |                      |                     |0.047***             |
|Log Real GDP Per Capita                     |std.error |                     |                      |                     |(0.011)              |
|Local Unemployment Rate                     |estimate  |                     |                      |                     |-0.048***            |
|Local Unemployment Rate                     |std.error |                     |                      |                     |(0.010)              |
|Num.Obs.                                    |          |248093               |248093                |168813               |157873               |
|R2                                          |          |0.016                |0.025                 |0.754                |0.809                |
|R2 Adj.                                     |          |0.016                |0.025                 |0.691                |0.759                |
|FE: segment_id^year                         |          |                     |                      |X                    |X                    |
