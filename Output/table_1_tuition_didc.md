|term                                        |statistic |Tuition 1: Naive OLS |Tuition 2: Spatial RD |Tuition 3: Base DiDC |Tuition 4: Full DiDC |
|:-------------------------------------------|:---------|:--------------------|:---------------------|:--------------------|:--------------------|
|Tuition Gap LATE (S_i x Delta Tuition, $1k) |estimate  |-0.049**             |-0.031                |-0.019**             |-0.003               |
|Tuition Gap LATE (S_i x Delta Tuition, $1k) |std.error |(0.019)              |(0.021)               |(0.009)              |(0.013)              |
|Spatial Treatment (S_i)                     |estimate  |0.017                |-0.114*               |-0.104*              |0.009                |
|Spatial Treatment (S_i)                     |std.error |(0.068)              |(0.061)               |(0.053)              |(0.054)              |
|Tuition Gap (Delta Policy, $1k)             |estimate  |0.027                |0.042                 |                     |                     |
|Tuition Gap (Delta Policy, $1k)             |std.error |(0.026)              |(0.045)               |                     |                     |
|Effective Property Tax Rate                 |estimate  |                     |                      |                     |-21.296***           |
|Effective Property Tax Rate                 |std.error |                     |                      |                     |(3.063)              |
|State Income Tax Liability                  |estimate  |                     |                      |                     |0.000                |
|State Income Tax Liability                  |std.error |                     |                      |                     |(0.000)              |
|Log Real GDP Per Capita                     |estimate  |                     |                      |                     |0.047***             |
|Log Real GDP Per Capita                     |std.error |                     |                      |                     |(0.011)              |
|Local Unemployment Rate                     |estimate  |                     |                      |                     |-0.049***            |
|Local Unemployment Rate                     |std.error |                     |                      |                     |(0.010)              |
|Num.Obs.                                    |          |268224               |268224                |182576               |170498               |
|R2                                          |          |0.016                |0.024                 |0.762                |0.815                |
|R2 Adj.                                     |          |0.016                |0.024                 |0.701                |0.767                |
|FE: segment_id^year                         |          |                     |                      |X                    |X                    |
