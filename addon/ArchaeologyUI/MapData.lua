-- World bounds of the 3.3.5a world maps, so dig sites (world coordinates) can be placed on
-- whatever map is open. Same numbers as WorldMapArea.dbc: a point at world (x, y) sits at
--   map x = (left - y) / width,  map y = (top - x) / height
-- where left is the map's largest world y and top its largest world x.
--
-- ZONES is keyed by the map file name GetMapInfo() returns. Besides the stock zones it lists the
-- start-area and cave maps that the Project Reforged client mod adds; stock clients never show
-- those. The Burning Crusade start zones (Azuremyst, Bloodmyst, Eversong, Ghostlands, Quel'Danas
-- and their cities) are left out: they are on map 530 but drawn on the old continents' maps, and
-- no dig site is there.

local A = ArchaeologyUI

-- By GetCurrentMapContinent(): map, left, top, width, height
A.CONTINENTS = {
    [1] = { 1, 17066.60, 12799.90, 36800.21, 24533.03 },   -- Kalimdor
    [2] = { 0, 18171.97, 11176.34, 40741.18, 27149.80 },   -- Eastern Kingdoms
    [3] = { 530, 12996.04, 5821.36, 17463.99, 11642.36 },   -- Outland
    [4] = { 571, 9217.15, 10593.38, 17751.40, 11834.31 },   -- Northrend
}

-- map, left, top, width, height
A.ZONES = {
    -- Kalimdor
    Ashenvale = { 1, 1699.83, 4672.97, 5766.73, 3843.72 },
    Aszhara = { 1, -3277.30, 5341.72, 5070.89, 3381.23 },
    BanethilBarrowden4_ = { 1, 1684.86, 9881.68, 230.01, 153.34 },
    BanethilBarrowden5_ = { 1, 1734.86, 9931.68, 380.01, 253.34 },
    Barrens = { 1, 2622.76, 1612.58, 10133.44, 6756.20 },
    BurningBladeCoven8_ = { 1, -4166.71, 5.58, 266.00, 177.33 },
    CampNaracheStart = { 1, 233.17, -2576.99, 1766.67, 1177.08 },
    CavernsofTime17_ = { 1, -4163.93, -7955.70, 1107.51, 738.34 },
    CavernsofTime18_ = { 1, -3707.69, -8036.53, 1306.00, 870.67 },
    Darkshore = { 1, 2941.51, 8333.36, 6550.07, 4366.64 },
    Darnassis = { 1, 2938.21, 10238.33, 1058.34, 705.72 },
    Desolace = { 1, 4233.19, 452.17, 4495.88, 2997.90 },
    Durotar = { 1, -1962.71, 1808.41, 5287.56, 3524.98 },
    Dustwallow = { 1, -975.20, -2033.23, 5250.06, 3499.98 },
    DustwindCave19_ = { 1, -4622.71, 971.33, 258.00, 172.00 },
    FelRock3_ = { 1, 1249.66, 10211.71, 279.60, 186.40 },
    Felwood = { 1, 1641.50, 7133.37, 5750.06, 3833.31 },
    Feralas = { 1, 5441.54, -2366.56, 6950.07, 4633.30 },
    GMIsland = { 1, 16747.85, 16525.02, 828.00, 541.00 },
    Hyjal = { 1, -1139.15, 6085.94, 3195.89, 2129.07 },
    MaraudonOutside21_ = { 1, 3085.36, -1249.91, 600.00, 400.00 },
    MaraudonOutside22_ = { 1, 3164.87, -1092.24, 560.02, 373.35 },
    Moonglade = { 1, -1381.45, 8491.70, 2308.36, 1539.57 },
    Mulgore = { 1, 2047.75, -272.82, 5137.56, 3424.98 },
    Ogrimmar = { 1, -3680.83, 2273.95, 1402.62, 935.41 },
    Ogrimmar1_ = { 1, -4164.20, 1932.34, 362.09, 241.39 },
    PalemaneRock6_ = { 1, 579.84, -2263.24, 350.01, 233.34 },
    ShadowglenStart = { 1, 1491.52, 11033.34, 1450.00, 966.67 },
    ShadowthreadCave2_ = { 1, 1139.86, 11035.01, 480.00, 320.00 },
    Silithus = { 1, 2537.34, -5958.20, 3483.37, 2322.90 },
    SkullRock12_ = { 1, -4629.21, 1580.58, 270.00, 180.00 },
    StonetalonMountains = { 1, 3245.68, 2916.74, 4883.39, 3256.23 },
    Tanaris = { 1, -218.94, -5874.87, 6900.08, 4599.97 },
    Teldrassil = { 1, 3814.44, 11831.26, 5091.72, 3393.73 },
    TheGapingChasm16_ = { 1, -3612.69, -8899.87, 885.00, 590.00 },
    TheNoxiousLair15_ = { 1, -2190.19, -7639.87, 750.00, 500.00 },
    TheSlitheringScar14_ = { 1, -983.93, -7929.87, 382.50, 255.00 },
    TheVentureCoMine7_ = { 1, -818.16, -1435.91, 741.00, 494.00 },
    ThousandNeedles = { 1, -433.52, -3966.55, 4400.05, 2933.31 },
    ThunderBluff = { 1, 516.49, -849.90, 1043.76, 695.83 },
    TiragardeKeep10_ = { 1, -5052.71, -203.25, 125.00, 83.33 },
    TiragardeKeep11_ = { 1, -5052.71, -203.25, 125.00, 83.33 },
    TwilightsRun13_ = { 1, 161.10, -6183.20, 252.51, 168.34 },
    UngoroCrater = { 1, 533.15, -5966.53, 3700.04, 2466.65 },
    ValleyofTrialsStart = { 1, -3641.87, 0.08, 1350.00, 900.00 },
    WailingCavernsBarrens20_ = { 1, -1902.66, -489.92, 570.00, 380.00 },
    Winterspring = { 1, -316.86, 8533.36, 7100.08, 4733.30 },
    -- Eastern Kingdoms
    Alterac = { 0, 783.34, 1499.96, 2800.00, 1866.67 },
    Arathi = { 0, -866.66, -133.38, 3600.00, 2400.01 },
    Badlands = { 0, -2079.16, -5889.65, 2487.50, 1658.34 },
    BlackrockMountain14_ = { 0, -761.25, -7325.08, 712.50, 475.00 },
    BlackrockMountain15_ = { 0, -1145.00, -7480.08, 255.00, 170.00 },
    BlackrockMountain16_ = { 0, -627.48, -7086.73, 760.02, 506.68 },
    BlastedLands = { 0, -1241.66, -10566.76, 3350.00, 2233.34 },
    BurningSteppes = { 0, -266.66, -7031.33, 2929.17, 1952.09 },
    ColdridgePass6_ = { 0, 245.00, -6020.06, 330.00, 220.00 },
    ColdridgeValley = { 0, 979.17, -5962.56, 964.58, 643.75 },
    DeadminesWestfall17_ = { 0, 1792.50, -11055.09, 450.00, 300.00 },
    DeadwindPass = { 0, -833.33, -9866.75, 2500.00, 1666.67 },
    DeathknellStart = { 0, 2147.92, 2270.80, 1089.58, 727.08 },
    DunMorogh = { 0, 1802.09, -3877.15, 4925.00, 3283.35 },
    Duskwood = { 0, 833.34, -9716.75, 2700.00, 1800.01 },
    EasternPlaguelands = { 0, -2287.50, 3704.13, 4031.25, 2687.51 },
    EchoRidgeMine3_ = { 0, -27.00, -8500.08, 279.00, 186.00 },
    Elwynn = { 0, 1535.42, -7939.66, 3470.83, 2314.59 },
    Fargodeepmine1_ = { 0, 281.75, -9700.08, 240.00, 160.00 },
    Fargodeepmine2_ = { 0, 289.25, -9710.08, 255.00, 170.00 },
    FrostmaneHold8_ = { 0, 848.06, -5484.85, 341.88, 234.39 },
    FrostmaneHovel9_ = { 0, 508.25, -6445.73, 266.49, 177.66 },
    GnomereganEntrance10_ = { 0, 1082.93, -4762.95, 730.49, 467.23 },
    GolBolarQuarry11_ = { 0, -1542.99, -5486.89, 374.01, 249.34 },
    GoldCoastQuarry4_ = { 0, 2096.25, -10430.09, 262.50, 175.00 },
    Hilsbrad = { 0, 1066.67, 399.95, 3200.00, 2133.34 },
    Hinterlands = { 0, -1575.00, 1466.62, 3850.00, 2566.68 },
    Ironforge = { 0, -713.59, -4569.31, 790.63, 527.61 },
    JangolodeMine5_ = { 0, 1570.50, -9798.75, 277.00, 184.67 },
    JasperlodeMine19_ = { 0, -445.87, -8985.08, 323.25, 215.50 },
    LochModan = { 0, -1993.75, -4487.57, 2758.33, 1839.59 },
    NightWebsHollow12_ = { 0, 2020.00, 2123.30, 220.00, 146.67 },
    Northshire = { 0, 187.50, -8570.91, 968.75, 645.83 },
    Redridge = { 0, -1570.83, -8575.08, 2170.83, 1447.92 },
    ScarletMonasteryEntrance13_ = { 0, -660.00, 2948.80, 204.99, 136.66 },
    SearingGorge = { 0, -322.91, -6100.07, 2231.25, 1487.51 },
    Silverpine = { 0, 3450.00, 1666.63, 4200.00, 2800.01 },
    Stormwind = { 0, 1722.92, -7995.91, 1737.50, 1158.34 },
    Stranglethorn = { 0, 2220.83, -11168.84, 6381.25, 4254.18 },
    SwampOfSorrows = { 0, -2222.91, -9620.92, 2293.75, 1529.17 },
    TheGrizzledDen7_ = { 0, 32.75, -5313.06, 505.50, 337.00 },
    Tirisfal = { 0, 3033.33, 3837.47, 4518.75, 3012.51 },
    Uldaman18_ = { 0, -2748.75, -5955.07, 562.50, 375.00 },
    Undercity = { 0, 873.19, 1877.90, 959.37, 640.11 },
    WesternPlaguelands = { 0, 416.67, 3366.63, 4300.00, 2866.68 },
    Westfall = { 0, 3016.67, -9400.09, 3500.00, 2333.34 },
    Wetlands = { 0, -389.58, -2147.97, 4135.42, 2756.26 },
    -- Outland
    BladesEdgeMountains = { 530, 8845.86, 4408.38, 5424.97, 3616.55 },
    Hellfire = { 530, 5539.62, 1481.39, 5164.56, 3443.64 },
    Nagrand = { 530, 10295.85, 41.85, 5524.97, 3683.22 },
    Netherstorm = { 530, 5483.37, 5456.26, 5574.97, 3716.55 },
    ShadowmoonValley = { 530, 4225.05, -1947.67, 5499.97, 3666.55 },
    ShattrathCity = { 530, 6135.30, -1473.73, 1306.24, 870.81 },
    TerokkarForest = { 530, 7083.36, -999.79, 5399.97, 3599.89 },
    Zangarmarsh = { 530, 9475.02, 1935.54, 5027.06, 3351.98 },
    -- Northrend
    BoreanTundra = { 571, 8570.83, 4897.90, 5764.58, 3843.76 },
    CrystalsongForest = { 571, 1443.75, 6502.07, 2722.92, 1814.59 },
    Dalaran = { 571, 1052.51, 6066.66, 830.01, 553.34 },
    Dragonblight = { 571, 3627.08, 5574.99, 5608.33, 3739.60 },
    GrizzlyHills = { 571, -1110.42, 5516.65, 5250.00, 3500.01 },
    HowlingFjord = { 571, -1397.92, 3116.64, 6045.83, 4031.27 },
    HrothgarsLanding = { 571, 2797.92, 10781.26, 3677.08, 2452.09 },
    IcecrownGlacier = { 571, 5443.75, 9427.08, 6270.83, 4181.27 },
    LakeWintergrasp = { 571, 4329.16, 5716.65, 2975.00, 1983.34 },
    SholazarBasin = { 571, 6929.16, 7287.49, 4356.25, 2904.18 },
    TheStormPeaks = { 571, 1841.67, 10197.92, 7112.50, 4741.68 },
    ZulDrak = { 571, -600.00, 7668.74, 4993.75, 3329.18 },
}
