|term                                        |statistic |Joint 1: Naive OLS |Joint 2: Spatial RD |Joint 3: Base DiDC |Joint 4: Full DiDC |
|:-------------------------------------------|:---------|:------------------|:-------------------|:------------------|:------------------|
|Tuition Gap LATE (S_i x Delta Tuition, $1k) |estimate  |-0.053***          |-0.035*             |-0.016*            |-0.003             |
|Tuition Gap LATE (S_i x Delta Tuition, $1k) |std.error |(0.017)            |(0.018)             |(0.009)            |(0.010)            |
|Caliber Gap LATE (S_i x Delta Caliber)      |estimate  |0.044              |0.034               |0.038              |0.028              |
|Caliber Gap LATE (S_i x Delta Caliber)      |std.error |(0.041)            |(0.032)             |(0.027)            |(0.024)            |
|Spatial Treatment (S_i)                     |estimate  |0.003              |-0.104*             |-0.117**           |-0.037             |
|Spatial Treatment (S_i)                     |std.error |(0.061)            |(0.061)             |(0.051)            |(0.047)            |
|Tuition Gap (Delta Policy, $1k)             |estimate  |0.040              |0.055               |                   |                   |
|Tuition Gap (Delta Policy, $1k)             |std.error |(0.025)            |(0.045)             |                   |                   |
|Caliber Gap (Delta Policy)                  |estimate  |-0.085*            |-0.112**            |                   |                   |
|Caliber Gap (Delta Policy)                  |std.error |(0.046)            |(0.052)             |                   |                   |
|Effective Property Tax Rate                 |estimate  |                   |                    |                   |-19.369***         |
|Effective Property Tax Rate                 |std.error |                   |                    |                   |(3.042)            |
|State Income Tax Liability                  |estimate  |                   |                    |                   |0.000              |
|State Income Tax Liability                  |std.error |                   |                    |                   |(0.000)            |
|Log Real GDP Per Capita                     |estimate  |                   |                    |                   |0.036***           |
|Log Real GDP Per Capita                     |std.error |                   |                    |                   |(0.009)            |
|Local Unemployment Rate                     |estimate  |                   |                    |                   |-0.050***          |
|Local Unemployment Rate                     |std.error |                   |                    |                   |(0.009)            |
|Num.Obs.                                    |          |212486             |212486              |146347             |138635             |
|R2                                          |          |0.047              |0.057               |0.761              |0.819              |
|R2 Adj.                                     |          |0.047              |0.057               |0.697              |0.770              |
|FE: segment_id^year                         |          |                   |                    |X                  |X                  |
