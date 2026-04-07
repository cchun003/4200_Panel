# Session Conclusions: Isolation of Higher Education Capitalization
**Date:** April 7, 2026
**Lead Researcher:** Chen Chun
**Assistant:** Antigravity (Gemini)

## 1. Problem Statement
Initial DiDC models showed insignificant results for Tuition and Institutional Caliber (Top 100) once saturated with `segment_id^year` fixed effects and local macroeconomic covariates (GDP, Unemployment, Property Tax). Standard errors were over-inflated by strict two-way clustering (`~ zcta + border_dyad`).

## 2. Theoretical Breakthrough: The Top 50 "Elite" Cliff
We hypothesized that the option-value of higher education is strictly non-linear. Sorting behavior is not driven by access to any flagship school, but specifically by access to **Elite Public Ivies (Top 50 tier)**.

### Empiricial Evidence:
- **Baseline (Top 100):** Coefficient was $0.028$ and insignificant under two-way clustering.
- **Heterogeneity Trial (Top 50):** Coefficient tripled to **$0.090$** and became statistically significant at the **1% level ($p < 0.01$)** even under strict two-way clustering.
- **Conclusion:** Households capitalize approximately **9%** into housing prices for access to Top 50 university systems across state borders.

## 3. Pure Price vs. Prestige Elasticity
- By restricting the sample to border ZCTAs with an identical number of Top 50 institutions (holding caliber constant), the **Tuition Gap LATE** remained flat ($-0.003$) and insignificant.
- **Inference:** In the spatial equilibrium of housing markets, prestige (Caliber) is the primary driver of sorting, while the raw financial tuition differential is secondary or dominated by other tax/macro factors.

## 4. Path Forward (Planned in plans.txt)
1. **Marginal Tax Cliff:** Preliminary findings show the tuition coefficient flips from negative to positive ($+0.012$) when restricted to borders with identical state income tax regimes.
2. **Reciprocity Adjustments:** Flagging Western Undergraduate Exchange (WUE) and MHEC borders to isolate where the tuition cliff is artificially removed.
3. **Spatial Decay:** Implementing distance-to-campus filters to see if capitalization decays as ZCTAs get further from the flagship campus.
4. **Architectural Controls:** Moving to Python pipeline (Tasks 1.2/1.3) to query ACS for Median Home Age and Median Rooms to further tighten standard errors.
