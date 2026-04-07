|term                                        |statistic |Joint 1: Naive OLS |Joint 2: Spatial RD |Joint 3: Base DiDC |Joint 4: Full DiDC |
|:-------------------------------------------|:---------|:------------------|:-------------------|:------------------|:------------------|
|Tuition Gap LATE (S_i x Delta Tuition, $1k) |estimate  |-0.057***          |-0.043*             |-0.026***          |-0.008             |
|Tuition Gap LATE (S_i x Delta Tuition, $1k) |std.error |(0.020)            |(0.022)             |(0.009)            |(0.013)            |
|Caliber Gap LATE (S_i x Top 50 Caliber)     |estimate  |-0.020             |0.039               |0.093**            |0.098***           |
|Caliber Gap LATE (S_i x Top 50 Caliber)     |std.error |(0.040)            |(0.047)             |(0.041)            |(0.031)            |
|Spatial Treatment (S_i)                     |estimate  |-0.022             |-0.118              |-0.131**           |-0.039             |
|Spatial Treatment (S_i)                     |std.error |(0.074)            |(0.071)             |(0.054)            |(0.052)            |
|Tuition Gap (Delta Policy, $1k)             |estimate  |0.047              |0.068               |                   |                   |
|Tuition Gap (Delta Policy, $1k)             |std.error |(0.029)            |(0.050)             |                   |                   |
|Top 50 Caliber Gap (Delta Policy)           |estimate  |0.017              |-0.061              |                   |                   |
|Top 50 Caliber Gap (Delta Policy)           |std.error |(0.055)            |(0.091)             |                   |                   |
|Effective Property Tax Rate                 |estimate  |                   |                    |                   |-19.494***         |
|Effective Property Tax Rate                 |std.error |                   |                    |                   |(3.081)            |
|State Income Tax Liability                  |estimate  |                   |                    |                   |0.000              |
|State Income Tax Liability                  |std.error |                   |                    |                   |(0.000)            |
|Federal Income Tax Liability                |estimate  |                   |                    |                   |0.000***           |
|Federal Income Tax Liability                |std.error |                   |                    |                   |(0.000)            |
|Log Real GDP Per Capita                     |estimate  |                   |                    |                   |0.039***           |
|Log Real GDP Per Capita                     |std.error |                   |                    |                   |(0.009)            |
|Local Unemployment Rate                     |estimate  |                   |                    |                   |-0.046***          |
|Local Unemployment Rate                     |std.error |                   |                    |                   |(0.009)            |
|Num.Obs.                                    |          |196632             |196632              |135402             |128420             |
|R2                                          |          |0.028              |0.039               |0.753              |0.812              |
|R2 Adj.                                     |          |0.028              |0.039               |0.687              |0.762              |
|FE: segment_id^year                         |          |                   |                    |X                  |X                  |
