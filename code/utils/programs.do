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
    syntax varname

    confirm variable `varlist'

    capture drop partner_group
    gen str10 partner_group = ""

    * Individual countries
    replace partner_group = "China"    if `varlist' == "5700"
    replace partner_group = "Canada"   if `varlist' == "1220"
    replace partner_group = "Mexico"   if `varlist' == "2010"
    replace partner_group = "Japan"    if `varlist' == "5880"
    replace partner_group = "S. Korea" if `varlist' == "5800"
    replace partner_group = "UK"       if `varlist' == "4120"

    * EU27 member states -- max 9 values per string inlist()
    replace partner_group = "EU" if inlist(`varlist', ///
        "4280", "4220", "4230", "4240", "4253", "4254", "4270", ///
        "4350", "4360")
    replace partner_group = "EU" if inlist(`varlist', ///
        "4380", "4390", "4550", "4560", "4570", "4590", "4610", ///
        "4690", "4700")
    replace partner_group = "EU" if inlist(`varlist', ///
        "4720", "4740", "4810", "4760", "4770", "4780", "4840", ///
        "4850", "4870")

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
    args num den newvar default

    if "`default'" == "" local default = .

    capture drop `newvar'
    gen double `newvar' = `num' / `den' if `den' != 0 & !missing(`den')
    replace `newvar' = `default' if missing(`newvar')
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
