# Crate names (keys) plus a name->itemID hint for each material. gen.py takes the real fill options
# from each crate's tooltip on Wowhead Forever and reports any difference from these.
# Crate definitions (from method.gg WoW Forever guide). (qty, name, itemID)
CRATES = {
  "Apprentice Ore": [(20, "Copper Ore", 2770), (20, "Tin Ore", 2771)],
  "Journeyman Ore": [(10, "Silver Ore", 2775), (20, "Iron Ore", 2772)],
  "Expert Ore": [(10, "Gold Ore", 2776), (20, "Mithril Ore", 3858)],
  "Artisan Ore": [(10, "Truesilver Ore", 7911), (20, "Thorium Ore", 10620), (20, "Dark Iron Ore", 11370)],

  "Apprentice Ingots": [(20, "Copper Bar", 2840), (20, "Tin Bar", 3576), (10, "Bronze Bar", 2841)],
  "Journeyman Ingots": [(10, "Silver Bar", 2842), (20, "Iron Bar", 3575)],
  "Expert Ingots": [(20, "Mithril Bar", 3860), (15, "Steel Bar", 3859), (10, "Gold Bar", 3577)],
  "Artisan Ingots": [(2, "Dark Iron Bar", 11371), (10, "Truesilver Bar", 6037), (20, "Thorium Bar", 12359)],

  "Apprentice Herbs": [(20, "Peacebloom", 2447), (20, "Silverleaf", 765), (10, "Earthroot", 2449), (10, "Mageroyal", 785), (10, "Briarthorn", 2450)],
  "Journeyman Herbs": [(10, "Stranglekelp", 3820), (10, "Bruiseweed", 2453), (10, "Wild Steelbloom", 3355), (10, "Grave Moss", 3369), (10, "Kingsblood", 3356)],
  "Earthly Expert Herbs": [(20, "Liferoot", 3357), (10, "Fadeleaf", 3818), (10, "Goldthorn", 3821), (10, "Khadgar's Whisker", 3358)],
  "Flowering Expert Herbs": [(10, "Wintersbite", 3819), (10, "Firebloom", 4625), (20, "Purple Lotus", 8831), (10, "Arthas' Tears", 8836)],
  "Earthly Artisan Herbs": [(10, "Golden Sansam", 13464), (20, "Sungrass", 8838), (10, "Blindweed", 8839), (10, "Ghost Mushroom", 8845), (10, "Gromsblood", 8846)],
  "Flowering Artisan Herbs": [(20, "Dreamfoil", 13463), (20, "Mountain Silversage", 13465), (20, "Plaguebloom", 13466), (20, "Icecap", 13467)],

  "Apprentice Parts": [(16, "Handful of Copper Bolts", 4359), (16, "Copper Tube", 4361), (4, "Copper Modulator", 4363)],
  "Journeyman Parts": [(8, "Bronze Tube", 4371), (7, "Whirring Bronze Gizmo", 4375), (4, "Bronze Framework", 4382), (45, "Gold Power Core", 10558)],
  "Expert Parts": [(8, "Iron Strut", 4387), (5, "Mithril Tube", 10559), (12, "Unstable Trigger", 10560), (5, "Mithril Casing", 10561)],
  "Artisan Parts": [(5, "Thorium Widget", 15994), (5, "Truesilver Transformer", 18631), (2, "Thorium Tube", 16000)],

  "Apprentice Textiles": [(40, "Linen Cloth", 2589), (20, "Light Leather", 2318)],
  "Journeyman Textiles": [(20, "Wool Cloth", 2592), (40, "Silk Cloth", 4306), (20, "Medium Leather", 2319)],
  "Expert Textiles": [(40, "Mageweave Cloth", 4338), (20, "Heavy Leather", 4234)],
  "Artisan Textiles": [(40, "Runecloth", 14047), (20, "Thick Leather", 4304), (20, "Rugged Leather", 8170)],

  "Apprentice Fabrics": [(2, "Cured Light Hide", 4231), (20, "Bolt of Linen Cloth", 2996)],
  "Journeyman Fabrics": [(6, "Bolt of Woolen Cloth", 2997), (10, "Bolt of Silk Cloth", 4305), (2, "Cured Medium Hide", 4233)],
  "Expert Fabrics": [(8, "Bolt of Mageweave", 4339), (2, "Cured Heavy Hide", 4236)],
  "Artisan Fabrics": [(8, "Bolt of Runecloth", 14048), (2, "Cured Thick Hide", 8172)],

  "Apprentice Curiosities": [(20, "Strange Dust", 10940), (4, "Greater Magic Essence", 10939), (6, "Small Glimmering Shard", 10978), (2, "Large Glimmering Shard", 11084)],
  "Journeyman Curiosities": [(20, "Soul Dust", 11083), (4, "Greater Astral Essence", 11082), (6, "Small Glowing Shard", 11138), (2, "Large Glowing Shard", 11139)],
  "Expert Curiosities": [(20, "Vision Dust", 11137), (4, "Greater Mystic Essence", 11135), (6, "Small Radiant Shard", 11177), (2, "Large Radiant Shard", 11178)],
  "Artisan Curiosities": [(20, "Dream Dust", 11176), (4, "Greater Nether Essence", 11175), (6, "Small Brilliant Shard", 14343), (2, "Large Brilliant Shard", 14344)],
}

LEVELS = {"Apprentice": 10, "Journeyman": 10, "Expert": 20, "Artisan": 35}
