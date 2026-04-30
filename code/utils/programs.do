* ==============================================================================
* programs.do
* Creator: John Iselin
* Date: April 2026
* Purpose: Reusable programs and label definitions for tariff-etr-eval.
*          Sourced by 00_etr_eval.do after globals.do.
* ==============================================================================


* ==============================================================================
* PROGRAM: assign_partner_group
*
* Creates variable `partner_group` from Census country code variable.
* Maps individual countries (China, Canada, Mexico, Japan, S. Korea, UK),
* EU27 member states, and everything else to ROW.
*
* Usage: assign_partner_group cty_code
* ==============================================================================

capture program drop assign_partner_group
program define assign_partner_group
    version 17.0
    syntax varname

    confirm variable `varlist'

    capture drop partner_group
    gen str10 partner_group = ""

    * Individual countries (codes from globals.do)
    replace partner_group = "China"    if `varlist' == "$cty_china"
    replace partner_group = "Canada"   if `varlist' == "$cty_canada"
    replace partner_group = "Mexico"   if `varlist' == "$cty_mexico"
    replace partner_group = "Japan"    if `varlist' == "$cty_japan"
    replace partner_group = "S. Korea" if `varlist' == "$cty_skorea"
    replace partner_group = "UK"       if `varlist' == "$cty_uk"

    * EU27 member states -- inlist() capped at 9 string args, so we split
    * into three batches defined in globals.do.
    replace partner_group = "EU" if inlist(`varlist', $eu_codes_1)
    replace partner_group = "EU" if inlist(`varlist', $eu_codes_2)
    replace partner_group = "EU" if inlist(`varlist', $eu_codes_3)

    * Rest of World
    replace partner_group = "ROW" if partner_group == ""
end


* ==============================================================================
* PROGRAM: safe_divide
*
* Creates new variable = numerator / denominator, with missing when denom is 0.
*
* Usage: safe_divide numerator denominator new_varname [default_value]
* ==============================================================================

capture program drop safe_divide
program define safe_divide
    version 17.0
    args num den newvar default

    if "`default'" == "" local default = .

    capture drop `newvar'
    gen double `newvar' = `num' / `den' if `den' != 0 & !missing(`den')
    replace `newvar' = `default' if missing(`newvar')
end


* ==============================================================================
* PROGRAM: report_merge
*
* Reports match / master / using counts from the _merge variable left by a
* preceding `merge` command, using a caller-supplied label for context.
* Assumes the standard _merge variable name (call before dropping it).
*
* Usage:
*   merge 1:1 hs10 cty_code ym using `cf_2024', keepusing(r) keep(match master)
*   report_merge "S0 vs cf_2024"
*   drop _merge
* ==============================================================================

capture program drop report_merge
program define report_merge
    version 17.0
    args label

    capture confirm variable _merge
    if _rc != 0 {
        di as error "report_merge: _merge not found (did you use gen(_merge)?)"
        exit 111
    }

    qui count if _merge == 3
    local n_match = r(N)
    qui count if _merge == 1
    local n_master = r(N)
    qui count if _merge == 2
    local n_using = r(N)
    local n_tot = `n_match' + `n_master' + `n_using'
    local pct = cond(`n_tot' > 0, 100 * `n_match' / `n_tot', 0)

    di as text "        [merge] `label': matched=`n_match'" ///
        " master-only=`n_master' using-only=`n_using'" ///
        " (" %4.1f `pct' "%)"
end


* ==============================================================================
* PROGRAM: build_month_rev_map
*
* Builds a ym -> revision crosswalk for the analysis window. Maps each month
* to the active HTS revision (latest revision with effective date on or
* before the first of the month). Uses $start_ym and $end_ym from globals.do
* and the revision_dates dta from $working (override via using()).
*
* Side effects: clears the in-memory dataset. Wrap the call in
* preserve/restore if the caller's in-memory data must be retained.
*
* Usage:
*   tempfile month_rev_map
*   build_month_rev_map, saving(`month_rev_map')
*   merge m:1 ym using `month_rev_map', keep(match master) nogenerate
* ==============================================================================

capture program drop build_month_rev_map
program define build_month_rev_map
    version 17.0
    syntax , Saving(string) [USing(string)]

    if "`using'" == "" local using "${working}/revision_dates.dta"

    * Validate the using file before crossing
    capture confirm file "`using'"
    if _rc != 0 {
        di as error "build_month_rev_map: using file not found: `using'"
        error 601
    }

    clear
    local n_months = $end_ym - $start_ym + 1
    set obs `n_months'
    gen int ym = $start_ym + _n - 1
    format ym %tm
    gen first_of_month = dofm(ym)
    format first_of_month %td

    cross using "`using'"

    * Validate that cross produced expected columns
    foreach v in revision eff_date {
        capture confirm variable `v'
        if _rc != 0 {
            di as error "build_month_rev_map: column '`v'' missing after cross"
            di as error "       (using file: `using')"
            error 111
        }
    }

    keep if eff_date <= first_of_month
    bysort ym (eff_date): keep if _n == _N
    keep ym revision

    * Final sanity: must have a revision per month in the window
    if _N != `n_months' {
        di as error "build_month_rev_map: expected `n_months' rows after filter," ///
                   " got " _N
        di as error "       (every month in the analysis window needs a revision;" ///
                   " check revision_dates.dta covers \$start_ym to \$end_ym)"
        error 459
    }

    save `"`saving'"', replace
end


* ==============================================================================
* PROGRAM: compute_tier
*
* Computes a one-line-per-month (or month x by-var) aggregate ETR tier by
* multiplying a rate column by a weight column over the currently-loaded
* panel, then collapsing. Operates on the in-memory dataset; caller is
* responsible for `preserve` / `restore` around the call.
*
* Expects the in-memory dataset to carry both the rate and weight columns
* on the same row (typical: merged_analysis.dta, which has rate_2024,
* rate_usmca_monthly, rate_all_pref, total_rate alongside imports and
* con_val_mo). No file I/O on input — only the collapsed output is saved.
*
* Side effects: collapses the in-memory dataset.
*
* Options:
*   ratevar()   Rate variable name in the in-memory data (required)
*   weightvar() Weight variable name in the in-memory data (required)
*   outfile()   Path/tempfile to save collapsed result (required)
*   outvar()    Name for the collapsed ETR in the output (required)
*   byvar()     Optional grouping variable for the collapse (e.g., partner_group)
*   percent     If set, multiply output ETR by 100 before saving
*
* Usage:
*   preserve
*       compute_tier, ratevar(rate_2024) weightvar(imports) ///
*           outfile(`tier_s0') outvar(s0) percent
*   restore
* ==============================================================================

capture program drop compute_tier
program define compute_tier
    version 17.0
    syntax , RATEvar(name) WEIGHTvar(name) ///
             OUTfile(string) OUTvar(name) ///
             [BYvar(name) PERCent]

    * Validate up-front so a typo produces a clean error with caller context
    * rather than a generic "variable not found" inside `gen ... = ratevar * weightvar`.
    confirm variable `ratevar'
    confirm variable `weightvar'
    if "`byvar'" != "" confirm variable `byvar'

    tempvar _wtd
    gen double `_wtd' = `ratevar' * `weightvar'

    if "`byvar'" == "" {
        collapse (sum) num=`_wtd' den=`weightvar', by(ym)
        safe_divide num den `outvar'
        if "`percent'" != "" replace `outvar' = `outvar' * 100
        keep ym `outvar'
    }
    else {
        collapse (sum) num=`_wtd' den=`weightvar', by(ym `byvar')
        safe_divide num den `outvar'
        if "`percent'" != "" replace `outvar' = `outvar' * 100
        keep ym `byvar' `outvar'
    }

    compress
    save `"`outfile'"', replace
end


* ==============================================================================
* PROGRAM: compute_diversion_decomp
*
* Shapley two-way decomposition of a "fixed-rate, weights-shift" gap. Used
* in the framework for the trade-diversion channel (S1 -> S2 in the current
* design): rate panel held at rate_h2avg, weights shift from 2024 annual
* (`imports`) to actual monthly (`con_val_mo`). Shapley splits the resulting
* aggregate gap cleanly into a between-group and within-group component:
*
*    gap = sum_g [0.5*(R_g_24 + R_g_mw)*(s_g_24 - s_g_mw)]   <-- between
*        + sum_g [0.5*(s_g_24 + s_g_mw)*(R_g_24 - R_g_mw)]   <-- within
*
* where g indexes the partition (partner_group or product_group), R_g is
* group g's value-weighted rate, s_g is group g's share of total imports.
* Sign convention: positive contribution = positive contribution to
* (S_2024-weighted - S_monthly-weighted) at the given rate panel.
*
* Operates on the in-memory dataset; caller is responsible for `preserve` /
* `restore`. The dataset must carry the named rate panel column, imports
* (2024 weight), con_val_mo (monthly weight), ym, and the byvar column.
*
* Side effects: collapses the in-memory dataset.
*
* Options:
*   RATEvar()       Rate column to hold fixed across the two weighting schemes
*                   (e.g. rate_h2avg for S1->S2, rate_2024 for S0->S1 holding
*                   USMCA at 2024 baseline -- not the framework channel)  [required]
*   BYvar()         Grouping variable (partner_group, product_group, ...) [required]
*   OUTfile()       Path/tempfile to save the (ym x byvar) panel          [required]
*   OUTvar_prefix() Prefix for between/within/total columns (e.g. "c", "p") [required]
*
* Output columns (all in pp): <prefix>_between, <prefix>_within, <prefix>_total.
*
* Usage:
*   preserve
*       compute_diversion_decomp, ratevar(rate_h2avg) byvar(partner_group) ///
*           outfile("$working/diversion_by_country.dta") outvar_prefix(c)
*   restore
* ==============================================================================

capture program drop compute_diversion_decomp
program define compute_diversion_decomp
    version 17.0
    syntax , RATEvar(name) BYvar(name) OUTfile(string) OUTvar_prefix(name)

    confirm variable `ratevar'
    confirm variable imports
    confirm variable con_val_mo
    confirm variable ym
    confirm variable `byvar'

    * Build group-level numerators (rate * weight) and weights.
    tempvar num_24 num_mw
    gen double `num_24' = `ratevar' * imports
    gen double `num_mw' = `ratevar' * con_val_mo

    collapse (sum) num_24=`num_24' num_mw=`num_mw' ///
                   imports con_val_mo, ///
        by(ym `byvar')

    * Total monthly weights for share computation (computed post-collapse).
    bysort ym: egen double tot_24 = total(imports)
    bysort ym: egen double tot_mw = total(con_val_mo)

    * Group-level rates and shares. Zero-fill missing rates (a group with
    * zero weight in one period has an undefined rate; convention: use 0
    * so it contributes nothing to that period's S, which is correct).
    safe_divide num_24    imports     R_24
    safe_divide num_mw    con_val_mo  R_mw
    safe_divide imports    tot_24      s_24
    safe_divide con_val_mo tot_mw      s_mw

    foreach v in R_24 R_mw s_24 s_mw {
        replace `v' = 0 if missing(`v')
    }

    * Shapley two-way decomposition. Sign: positive => positive contribution
    * to gap_diversion = (S0 - S1).
    gen double `outvar_prefix'_between = 0.5 * (R_24 + R_mw) * (s_24 - s_mw)
    gen double `outvar_prefix'_within  = 0.5 * (s_24 + s_mw) * (R_24 - R_mw)
    gen double `outvar_prefix'_total   = `outvar_prefix'_between + `outvar_prefix'_within

    * Convert to percentage points.
    foreach v in between within total {
        replace `outvar_prefix'_`v' = `outvar_prefix'_`v' * 100
    }

    label var `outvar_prefix'_between "Between-`byvar' contribution to S0-S1 (pp)"
    label var `outvar_prefix'_within  "Within-`byvar' contribution to S0-S1 (pp)"
    label var `outvar_prefix'_total   "Total `byvar' contribution to S0-S1 (pp)"

    keep ym `byvar' `outvar_prefix'_between `outvar_prefix'_within `outvar_prefix'_total
    sort ym `byvar'
    compress
    save `"`outfile'"', replace
end


* ==============================================================================
* PROGRAM: classify_pref_channel
*
* Creates `pref_channel` from (cty_subco, rate_prov, cty_code). Bins each
* row into one of nine channels:
*
*   usmca         -- CA/MX with S/S+ (or "CA"/"MX") preference codes
*   korus         -- KR preference code (any country)
*   other_fta     -- AU, IL, SG, CL, CO, PE, PA, JO, MA, OM, BH, P, P+, R, JP, NP
*   gsp_agoa      -- A, A+, A*, D, E, E*, J, J+, J*, W, Z, N
*   duty_free     -- rate_prov 10/18/19 (unclaimed duty-free)
*   ch99_dutiable -- rate_prov 69/79
*   mfn_dutiable  -- rate_prov 61/62/64/70
*   ftz_bonded    -- rate_prov 00 (deferred duties)
*   other         -- residual
*
* Order matters: preference codes (a-d) take precedence over rate-provision
* codes (e-i). A row tagged usmca by cty_subco stays usmca even if its
* rate_prov would otherwise classify it as duty_free.
*
* Inputs must all be string variables. Uses $cty_canada, $cty_mexico from
* globals.do for the USMCA country filter.
*
* Usage: classify_pref_channel cty_subco rate_prov cty_code
* ==============================================================================

capture program drop classify_pref_channel
program define classify_pref_channel
    version 17.0
    args subco rateprov cty

    confirm string variable `subco'
    confirm string variable `rateprov'
    confirm string variable `cty'

    * NOTE: Stata's string inlist() limit is 10 args (1 var + 9 strings).
    * Several batches below sit at exactly 8 or 9 strings. If you add a code
    * to a batch already at 9 (e.g., the GSP/AGOA list), Stata will error
    * with "too many string values" -- split the batch into a new line
    * rather than padding the existing one.

    capture drop pref_channel
    gen str20 pref_channel = ""

    * (a) USMCA: CA/MX with S/S+ preference codes
    replace pref_channel = "usmca" if ///
        inlist(`subco', "S", "S+", "CA", "MX") & ///
        inlist(`cty', "$cty_canada", "$cty_mexico")

    * (b) KORUS
    replace pref_channel = "korus" if `subco' == "KR"

    * (c) Other bilateral FTAs
    replace pref_channel = "other_fta" if pref_channel == "" & ///
        inlist(`subco', "AU", "IL", "SG", "CL", "CO", "PE", "PA", "JO")
    replace pref_channel = "other_fta" if pref_channel == "" & ///
        inlist(`subco', "MA", "OM", "BH", "P", "P+", "R", "JP", "NP")

    * (d) GSP / AGOA
    replace pref_channel = "gsp_agoa" if pref_channel == "" & ///
        inlist(`subco', "A", "A+", "A*", "D", "E", "E*", "J", "J+", "J*")
    replace pref_channel = "gsp_agoa" if pref_channel == "" & ///
        inlist(`subco', "W", "Z", "N")

    * (e-i) Rate provision based channels (only if no preference assigned)
    replace pref_channel = "duty_free"     if pref_channel == "" & ///
        inlist(`rateprov', "10", "18", "19")
    replace pref_channel = "ch99_dutiable" if pref_channel == "" & ///
        inlist(`rateprov', "69", "79")
    replace pref_channel = "mfn_dutiable"  if pref_channel == "" & ///
        inlist(`rateprov', "61", "62", "64", "70")
    replace pref_channel = "ftz_bonded"    if pref_channel == "" & `rateprov' == "00"
    replace pref_channel = "other"         if pref_channel == ""

    label var pref_channel "Preference/rate channel"
end


* ==============================================================================
* HS2 CHAPTER LABELS
* ==============================================================================

capture label drop hs2_lbl
label define hs2_lbl ///
     1 "Live Animals" ///
     2 "Meat" ///
     3 "Fish & Seafood" ///
     4 "Dairy, Eggs, Honey" ///
     5 "Other Animal Prod." ///
     6 "Live Plants" ///
     7 "Vegetables" ///
     8 "Fruits & Nuts" ///
     9 "Coffee, Tea, Spices" ///
    10 "Cereals" ///
    11 "Milling Products" ///
    12 "Oilseeds" ///
    13 "Gums & Resins" ///
    14 "Veg. Plaiting" ///
    15 "Fats & Oils" ///
    16 "Meat/Fish Prep." ///
    17 "Sugars" ///
    18 "Cocoa" ///
    19 "Cereal/Flour Prep." ///
    20 "Veg/Fruit Prep." ///
    21 "Misc. Food Prep." ///
    22 "Beverages" ///
    23 "Animal Feed" ///
    24 "Tobacco" ///
    25 "Salt, Stone" ///
    26 "Ores & Slag" ///
    27 "Mineral Fuels" ///
    28 "Inorganic Chem." ///
    29 "Organic Chem." ///
    30 "Pharmaceuticals" ///
    31 "Fertilizers" ///
    32 "Tanning/Dyeing" ///
    33 "Perfumery" ///
    34 "Soap & Waxes" ///
    35 "Albuminoids" ///
    36 "Explosives" ///
    37 "Photo Goods" ///
    38 "Misc. Chemicals" ///
    39 "Plastics" ///
    40 "Rubber" ///
    41 "Hides & Leather" ///
    42 "Leather Articles" ///
    43 "Fur" ///
    44 "Wood" ///
    45 "Cork" ///
    46 "Basketware" ///
    47 "Wood Pulp" ///
    48 "Paper" ///
    49 "Printed Material" ///
    50 "Silk" ///
    51 "Wool" ///
    52 "Cotton" ///
    53 "Other Veg. Fibers" ///
    54 "Man-Made Filaments" ///
    55 "Man-Made Staple" ///
    56 "Wadding/Nonwovens" ///
    57 "Carpets" ///
    58 "Special Woven" ///
    59 "Impregnated Textiles" ///
    60 "Knitted Fabrics" ///
    61 "Knitted Apparel" ///
    62 "Woven Apparel" ///
    63 "Other Textiles" ///
    64 "Footwear" ///
    65 "Headgear" ///
    66 "Umbrellas" ///
    67 "Feathers" ///
    68 "Stone/Cement" ///
    69 "Ceramics" ///
    70 "Glass" ///
    71 "Precious Metals" ///
    72 "Iron & Steel" ///
    73 "Steel Articles" ///
    74 "Copper" ///
    75 "Nickel" ///
    76 "Aluminum" ///
    78 "Lead" ///
    79 "Zinc" ///
    80 "Tin" ///
    81 "Other Base Metals" ///
    82 "Tools" ///
    83 "Metal Misc." ///
    84 "Machinery" ///
    85 "Electrical Equip." ///
    86 "Rail Vehicles" ///
    87 "Motor Vehicles" ///
    88 "Aircraft" ///
    89 "Ships & Boats" ///
    90 "Optical/Medical" ///
    91 "Clocks/Watches" ///
    92 "Musical Instruments" ///
    93 "Arms & Ammunition" ///
    94 "Furniture" ///
    95 "Toys & Games" ///
    96 "Misc. Manufactured" ///
    97 "Art & Antiques" ///
    98 "Special Imports" ///
    99 "Special Provisions"


* --- Confirmation ---
di as text "  programs.do loaded"
