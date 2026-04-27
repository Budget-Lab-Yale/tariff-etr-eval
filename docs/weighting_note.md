# Weighting the Statutory ETR: A Two-Stage Aggregation Problem

## Overview

Section 3 of the ETR evaluation report decomposes the gap between the statutory effective tariff rate (ETR) and actual customs collections into a **behavioral** component (importers shifting what and where they buy) and a **residual** (implementation and structural frictions). The decomposition requires computing the statutory ETR under two weighting schemes---2024 annual weights and actual monthly weights---using the same set of HS2 x country cell-level rates.

The statutory ETR reported in Section 3 using 2024 weights does not match the tariff-rate-tracker's published ETR. This note explains why.

## Available Data

The analysis draws on four datasets at different levels of granularity:

| Dataset | Granularity | Frequency | Source |
|---------|-------------|-----------|--------|
| HTS10 import weights | HTS10 x country | 2024 annual | Tariff-ETRs cache |
| Rate timeseries | HTS10 x country | By policy revision | Tariff-rate-tracker |
| Census trade data | HS10 x country | Monthly | Census IMDB bulk (parsed to HS10 detail; HS2 rollups derived via `substr(hs10,1,2)`) |
| Daily statutory ETR | Aggregate | Daily | Tariff-rate-tracker |

The key constraint: tracker rates are available at HTS10 x country only with 2024 annual weights. Monthly trade data is observed at HS10 x country (from the IMDB bulk parse) and rolled up to HS2 x country for this decomposition. The decomposition therefore requires a two-stage aggregation---HTS10 to HS2 x country, then HS2 x country to overall---to bridge tracker annual rates to monthly weights.

## Notation

Let $i$ index HTS10 products, $c$ countries, and $h$ HS2 chapters, with each product belonging to one chapter $h(i)$. Define:

- $r_{ic}(t)$: statutory tariff rate on product $i$ from country $c$ at date $t$
- $w_{ic}$: 2024 annual imports at HTS10 x country (from Tariff-ETRs cache)
- $W_{hc}$: 2024 annual imports at HS2 x country (HTS10 from Tariff-ETRs cache, aggregated to HS2)
- $W_{hc}^m$: month-$m$ 2025+ imports at HS2 x country (IMDB bulk HS10 detail, aggregated to HS2)

## The Tracker's ETR (One-Stage)

The tariff-rate-tracker computes the statutory ETR directly from HTS10-level data. Critically, the sum runs over **all** imported products, not just those subject to additional tariffs:

$$\text{ETR}^{\text{tracker}}(t) = \frac{\sum_{i,c}\, r_{ic}(t)\, w_{ic}}{\sum_{i,c}\, w_{ic}}$$

where $r_{ic}(t) = 0$ for products with no additional tariff. This is a single-stage weighted mean using a consistent set of weights throughout, with total imports in the denominator.

## The Report's ETR (Two-Stage, Original Code)

Because the decomposition operates at HS2 x country, the report must first collapse HTS10 rates to that level.

**Stage 1.** Within each HS2 x country cell, compute the import-weighted average rate using HTS10 weights:

$$\bar{r}_{hc}(t) = \frac{\sum_{i \in h}\, r_{ic}(t)\, w_{ic}}{\sum_{i \in h}\, w_{ic}}$$

**Stage 2.** Aggregate across cells. The original code weighted by HS2 x country imports (IMDB-derived):

$$\text{ETR}^{2024w}(t) = \frac{\sum_{h,c}\, \bar{r}_{hc}(t)\; W_{hc}}{\sum_{h,c}\, W_{hc}}$$

## Two Sources of Discrepancy

The original code had two compounding errors that caused it to report a statutory ETR of ~27% for February 2025, when the tracker reports 3.4%.

### (1) Denominator: excluding zero-tariff imports

The rate timeseries (`rate_timeseries.rds`) contains only products subject to additional tariffs. An `inner_join` between the snapshot and import weights dropped all zero-tariff products from both numerator and denominator. In February 2025, only 14% of imports (by value) were subject to additional tariffs---the other 86% disappeared from the calculation. The result was the average rate *conditional on being tariffed* (24.3%), not the overall ETR (3.4%).

**Fix:** Start from the full set of import weights and `left_join` the snapshot onto them, filling unmatched rates with zero. This keeps all $3,124B of imports in the denominator.

### (2) Outer weights: Census vs. HTS10-aggregated

Define $\tilde{W}_{hc} \equiv \sum_{i \in h} w_{ic}$, the HTS10-aggregated weight for each cell. The two-stage mean equals the one-stage mean if and only if the outer weights are proportional to the inner weights:

$$\text{ETR}^{2024w}(t) = \text{ETR}^{\text{tracker}}(t) \quad\Longleftrightarrow\quad W_{hc} \propto \tilde{W}_{hc} \;\;\forall\; h,c$$

In practice $W_{hc} \neq \tilde{W}_{hc}$ because the two come from different data sources (Census API vs. Tariff-ETRs cache), with differences in coverage, product classification, and country aggregation. The resulting discrepancy is:

$$\text{ETR}^{2024w}(t) - \text{ETR}^{\text{tracker}}(t) = \sum_{h,c}\, \bar{r}_{hc}(t)\left[\frac{W_{hc}}{\sum W_{hc}} - \frac{\tilde{W}_{hc}}{\sum \tilde{W}_{hc}}\right]$$

This added a further ~3 pp to the overstatement (within the already-inflated tariffed-only universe).

**Fix:** Use $\tilde{W}_{hc}$ (the HTS10-aggregated weights, stored as `imports_hs10` in the code) instead of $W_{hc}$ (Census) in Stage 2.

## Constructing Synthetic Monthly Weights

We observe HTS10-level imports only annually. To reweight by month, we want to construct synthetic monthly HTS10 weights $w_{ic}^m$ that (a) sum to Census monthly totals within each HS2 x country cell and (b) preserve the within-cell product composition from the annual data. The natural construction scales each HTS10 weight by the ratio of monthly to annual cell totals:

$$w_{ic}^m = w_{ic} \cdot \frac{W_{hc}^m}{\tilde{W}_{hc}}$$

By construction:
- $\sum_{i \in h} w_{ic}^m = W_{hc}^m$ (matches Census monthly totals)
- $w_{ic}^m / w_{jc}^m = w_{ic} / w_{jc}$ for $i, j \in h$ (within-cell composition unchanged)

The monthly-reweighted ETR using these synthetic weights is:

$$\text{ETR}^m(t) = \frac{\sum_{i,c}\, r_{ic}(t)\, w_{ic}^m}{\sum_{i,c}\, w_{ic}^m}$$

Substituting the definition of $w_{ic}^m$ and simplifying:

$$= \frac{\sum_{h,c}\; \frac{W_{hc}^m}{\tilde{W}_{hc}} \sum_{i \in h} r_{ic}(t)\, w_{ic}}{\sum_{h,c}\; W_{hc}^m} = \frac{\sum_{h,c}\; W_{hc}^m \cdot \bar{r}_{hc}(t)}{\sum_{h,c}\; W_{hc}^m}$$

This is **exactly the two-stage aggregation**: the HTS10 detail cancels out because within-cell composition is held fixed, leaving cell-level rates $\bar{r}_{hc}(t)$ weighted by Census monthly totals. The two-stage approach is not an approximation---it is algebraically equivalent to the synthetic-weight construction under the maintained assumption.

## Maintained Assumption

The within-cell product composition is assumed stable across months. If importers shift toward lower-tariff subcategories *within* an HS2 x country cell (e.g., substituting among machinery types within Ch. 84 from China), that response is not captured in the behavioral component and is absorbed into the residual. This is a data limitation---Census does not publish monthly HTS10 trade---not a modeling choice.

## Fix

Replace the Census weights $W_{hc}$ with the HTS10-aggregated weights $\tilde{W}_{hc}$ in Stage 2 of the 2024-weight calculation. The field `imports_hs10` in the intermediate table `stat_hs2_cty` already contains $\tilde{W}_{hc}$, so the change is a single substitution in the weighting argument. This makes the 2024-weight ETR exactly reproduce the tracker's one-stage result.

The actual-month ETR uses Census monthly weights $W_{hc}^m$, the only monthly data available:

$$\text{ETR}^{\text{actual-}w}(t,m) = \frac{\sum_{h,c}\, \bar{r}_{hc}(t)\; W_{hc}^m}{\sum_{h,c}\, W_{hc}^m}$$

The decomposition then cleanly isolates the behavioral reweighting effect:

$$\underbrace{\text{ETR}^{2024w} - \text{ETR}^{\text{treasury}}}_{\text{total gap}} \;=\; \underbrace{\text{ETR}^{2024w} - \text{ETR}^{\text{actual-}w}}_{\text{behavioral}} \;+\; \underbrace{\text{ETR}^{\text{actual-}w} - \text{ETR}^{\text{treasury}}}_{\text{residual}}
$$

With the fix, $\text{ETR}^{2024w}$ anchors to the tracker's published statutory rate, and the behavioral component captures the effect of shifting trade patterns across HS2 x country cells from 2024 annual to 2025 monthly composition---equivalent to reweighting HTS10 imports by monthly cell totals while holding within-cell product mix fixed.
