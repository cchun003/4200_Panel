# The Capitalization of Higher Education Subsidies into Local Housing Markets: A Spatial Difference-in-Discontinuities Approach

## 1. Introduction and Theoretical Framework

The spatial distribution of public goods and localized fiscal policies heavily influences household residential choices, fundamentally shaping the trajectory of regional housing markets across the United States. Historically, the theoretical foundation for this phenomenon is rooted in the **Tiebout model** of residential sorting, which posits that households "vote with their feet" by selecting jurisdictions that offer an optimal bundle of taxes and public amenities. Under the spatial equilibrium framework, any localized advantage—such as a superior school district, a lower property tax burden, or enhanced environmental amenities—is theoretically capitalized into local land rents and housing prices.

While the capitalization of highly localized public goods (notably K-12 school quality) has been extensively documented, the capitalization of broad, state-level higher education subsidies remains an under-explored frontier.

### The "Tuition Cliff"
State-funded public university systems in the U.S. operate under a residency-based dual-pricing model.
- **In-state residents:** Heavily discounted tuition.
- **Out-of-state students:** Substantial premiums (3-5x higher).
- **Option Value:** Residents of states with elite public university systems (e.g., CA, MI, VA, NC, TX) possess a valuable economic asset—the right to access prestigious education at a subsidized rate.

### Hypothesis
Households optimize utility by migrating across state borders to capture either immediate cost savings or the long-term option value of prestigious public flagships. This inter-state migration shifts demand curves in border housing markets, driving a localized price premium on the preferred side of the state boundary.

## 2. The Identification Challenge: Compound Treatments at State Borders

The primary empirical obstacle is the presence of **"compound treatments"** at administrative boundaries.
- **Strict Geographic Boundaries:** State lines define not just tuition eligibility, but also income tax brackets, property tax regimes, minimum wage laws, and social safety nets.
- **Endogenous Sorting:** Households deliberately choose their side of the border based on preferences, violating local randomization assumptions.

To overcome these challenges, we use a **Geographic Difference-in-Discontinuities (DiDC)** design, which synthesizes spatial RD with temporal Difference-in-Differences to effectively difference out time-invariant border confounders.

## 3. Implementation Guide: Econometric Specification and Data Workflow

This guide details the sequential, programmatic workflow for the analysis.

### Step 1: Programmatic Data Acquisition Workflow
**Optimal Language:** Hybrid (Python for APIs, R for Microsimulation)

- **Task 1.1: Federal and State Tax Liabilities via Synthetic Households (R)**
  - **Tooling:** `usincometaxes` package (wraps NBER TAXSIM 35).
  - **Logic:** Construct a synthetic "median homebuyer" profile. Map local median income and real estate taxes to TAXSIM inputs (`pwages`, `proptax`).
- **Task 1.2: Local Property Taxes and Demographics (Python)**
  - **Tooling:** `census` package.
  - **Logic:** Query ACS 5-year estimates at the ZCTA level. Calculate effective property tax rates.
- **Task 1.3: Local GDP and Labor Market Shocks (Python)**
  - **Tooling:** `beaapi` and `bls` packages.
  - **Logic:** Extract county-level GDP and Unemployment (LAUS). Map these to nested ZCTAs.

### Step 2: Geospatial Resolution and Bandwidth Selection
**Optimal Language:** Hybrid

- **Task 2.1: Geospatial Manipulation and Distance Calculations (Python)**
  - **Tooling:** `geopandas`.
  - **Logic:** Calculate shortest Euclidean distance from ZCTA centroids to state borders ($d_{ic}$). Normalize distance so $d_{ic}=0$ is the cutoff.
- **Task 2.2: Border Segment Creation (R)**
  - **Tooling:** `SpatialRDD`.
  - **Logic:** Partition state boundaries into ~50km equidistant segments.
- **Task 2.3: MSE-Optimal Bandwidth Selection (R)**
  - **Tooling:** `rdrobust`.
  - **Logic:** Calculate data-driven, MSE-optimal bandwidth ($h$) for each segment.

### Step 3: Econometric Specification Estimation (DiDC)
**Optimal Language:** R

**Model Specification:**
$$\ln(P_{ibt}) = \alpha + \tau (S_i \times \Delta Policy_{st}) + \beta_1 S_i + \beta_2 \Delta Policy_{st}$$
$$+ \gamma_1 d_{ic} + \gamma_2 (S_i \times d_{ic}) + \gamma_3 (d_{ic} \times \Delta Policy_{st}) + \gamma_4 (S_i \times d_{ic} \times \Delta Policy_{st})$$
$$+ \phi_{b,t} + \mathbf{X}_{ict}\lambda + \varepsilon_{ibt}$$

- **$\tau$:** Primary DiDC LATE estimator for tuition gap capitalization.
- **$\phi_{b,t}$:** Border-segment-by-year fixed effects.
- **$\mathbf{X}_{ict}$:** Matrix of time-varying confounders.

### Step 4: Confounder Mitigation and Spillover Adjustments
**Optimal Language:** R

- **Task 4.1: Mitigating SUTVA Violations (Spatial Spillovers)**
  - **Logic:** Control for spatial spillovers using distance-based treatment rings or "donut hole" regressions (dropping units within 1 mile of the boundary).

## 4. Robustness Checks and Falsification Tests

- **Placebo Border Test:** Shift the true state border (e.g., 50 miles inland) and re-estimate. $\tau$ should be statistically zero.
- **Pre-Trend Event Studies:** Interact spatial treatment with pre-treatment year dummies to verify parallel trends.

## 5. Conclusion

The DiDC model offers a robust solution to the identification problems inherent in spatial policy analysis. By leveraging longitudinal panel data and high-dimensional fixed effects, researchers can conclusively isolate the marginal capitalization of the "tuition cliff," providing insights into hidden spatial inequalities generated by higher education funding mechanisms.