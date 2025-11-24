# PLSS Vector Tiles Zoom Level Analysis

## Data Inventory

### ilmocplss.gdb
- **PLSSTownship**: 85,896 features (Multi Polygon)
  - Average area: 211M m² (~93 km² or 36 sq mi)
  - PLSS townships are 6 miles × 6 miles grids
  - Extent: Full CONUS coverage in Web Mercator

- **PLSSFirstDivision**: 2,776,408 features (Multi Polygon)
  - Average area: 6.4M m² (~2.5 km² or 1 sq mi)
  - PLSS sections are 1 mile × 1 mile grids
  - 36 sections per township typically

- **PLSSIntersected**: 27,338,029 features (Multi Polygon)
  - Average area: 689K m² (~0.26 km²)
  - Quarter sections, lots, and parcel subdivisions
  - Most detailed cadastral boundaries

### BOC_cb_2017_US_State_500k.gdb
- **cb_2017_us_state_500k**: 56 features (Multi Polygon)
  - US state boundaries (500k = 1:500,000 scale)
  - Already generalized for cartographic display

## Zoom Level Strategy

### Current Problem
- Tiles at z4 are 20-100MB each
- No zoom-level filtering or simplification
- All 27M+ features rendered at all zoom levels

### Recommended Zoom Ranges

| Layer | Min Zoom | Max Zoom | Features | Reasoning |
|-------|----------|----------|----------|-----------|
| **State Boundaries** | 0 | 6 | 56 | Context layer for low zoom |
| **Townships** | 7 | 14 | 85,896 | ~93 km² polygons visible at z7+ |
| **Sections** | 10 | 14 | 2.8M | ~2.5 km² polygons visible at z10+ |
| **Intersected** | 12 | 14 | 27.3M | ~0.26 km² parcels visible at z12+ |

### Web Mercator Tile Coverage Reference
- z0: 40,075 km per tile
- z4: 2,505 km per tile (current problematic zoom)
- z6: 626 km per tile
- z7: 313 km per tile
- z8: 156 km per tile
- z9: 78 km per tile
- z10: 39 km per tile
- z11: 19.5 km per tile
- z12: 9.75 km per tile
- z13: 4.88 km per tile
- z14: 2.44 km per tile

### Simplification Strategy

**Progressive Detail Approach:**

1. **z0-z6**: State boundaries only (highly simplified)
   - 56 features total
   - Heavy simplification acceptable
   - Tiles should be <10KB

2. **z7-z9**: Add townships (simplified)
   - 86K township polygons
   - Simplify to 10-20% of original detail
   - Drop sections and intersected
   - Target: <100KB per tile

3. **z10-z11**: Add sections (moderate simplification)
   - Townships at full detail
   - Sections at 30-50% detail
   - Drop intersected still
   - Target: <200KB per tile

4. **z12-z14**: Full detail
   - All layers at full resolution
   - Minimal simplification
   - Target: <500KB per tile

## Tippecanoe Parameters

### Key Parameters to Use:

```bash
--minimum-zoom=0
--maximum-zoom=14
--drop-densest-as-needed       # Auto-reduce feature density when tiles get too large
--extend-zooms-if-still-dropping  # Keep trying to include features at higher zooms
--maximum-tile-bytes=500000    # Hard limit: 500KB per tile
--simplification=10            # Aggressive simplification at lower zooms
--simplification-at-maximum-zoom=1  # Minimal simplification at z14
--detect-shared-borders        # Optimize polygon boundaries
--coalesce-densest-as-needed   # Merge small adjacent polygons at lower zooms
--no-feature-limit             # Allow all features (we're controlling by zoom)
--no-tile-size-limit           # Override default, use our --maximum-tile-bytes instead
```

### Layer-Specific Zoom Ranges:

```bash
# Option 1: Use name-based zoom filters
--named-layer=states:data/BOC_cb_2017_US_State_500k.gdb \
--named-layer=townships:data/ilmocplss.gdb:PLSSTownship \
--named-layer=sections:data/ilmocplss.gdb:PLSSFirstDivision \
--named-layer=intersected:data/ilmocplss.gdb:PLSSIntersected

# Then filter in processing (but tippecanoe doesn't have per-layer zoom control built-in)
# Alternative: Create separate MBTiles and merge, or use attribute filters
```

**Note**: Tippecanoe doesn't natively support per-layer min/max zoom in a single command. Solutions:

1. **Use tile-join to merge separate MBTiles** (recommended)
2. **Add zoom-level attributes and filter** (complex)
3. **Let drop-densest-as-needed handle it** (simple, but less control)

## Recommended Approach: Multi-Step Build

### Step 1: Build States (z0-z6)
```bash
tippecanoe \
  -o states.mbtiles \
  -Z0 -z6 \
  --layer=states \
  --simplification=20 \
  --maximum-tile-bytes=50000 \
  data/BOC_cb_2017_US_State_500k.gdb
```

### Step 2: Build Townships (z7-z14)
```bash
tippecanoe \
  -o townships.mbtiles \
  -Z7 -z14 \
  --layer=townships \
  --simplification=10 \
  --maximum-tile-bytes=200000 \
  --drop-densest-as-needed \
  data/ilmocplss.gdb PLSSTownship
```

### Step 3: Build Sections (z10-z14)
```bash
tippecanoe \
  -o sections.mbtiles \
  -Z10 -z14 \
  --layer=sections \
  --simplification=5 \
  --maximum-tile-bytes=300000 \
  --drop-densest-as-needed \
  data/ilmocplss.gdb PLSSFirstDivision
```

### Step 4: Build Intersected (z12-z14)
```bash
tippecanoe \
  -o intersected.mbtiles \
  -Z12 -z14 \
  --layer=intersected \
  --simplification=2 \
  --maximum-tile-bytes=500000 \
  --drop-densest-as-needed \
  --coalesce-densest-as-needed \
  data/ilmocplss.gdb PLSSIntersected
```

### Step 5: Merge All Layers
```bash
tile-join \
  -o blm-plss-cadastral-optimized.mbtiles \
  --no-tile-size-limit \
  states.mbtiles \
  townships.mbtiles \
  sections.mbtiles \
  intersected.mbtiles
```

## Expected Results

- **File size**: 10-20GB (down from 64GB)
- **Tile sizes**:
  - z0-z6: <50KB (states only)
  - z7-z9: <200KB (states + townships)
  - z10-z11: <300KB (states + townships + sections)
  - z12-z14: <500KB (all layers)
- **Tile count**: Reduced significantly by zoom filtering
- **Build time**: 2-4 hours (vs 8+ hours for original)

## Alternative: Single-Pass with drop-densest-as-needed

If tile-join is not available or multi-step is too complex:

```bash
tippecanoe \
  -o blm-plss-cadastral-optimized.mbtiles \
  -Z0 -z14 \
  --layer=states \
  --layer=townships \
  --layer=sections \
  --layer=intersected \
  --drop-densest-as-needed \
  --extend-zooms-if-still-dropping \
  --coalesce-densest-as-needed \
  --maximum-tile-bytes=500000 \
  --simplification=10 \
  --detect-shared-borders \
  --no-feature-limit \
  data/BOC_cb_2017_US_State_500k.gdb \
  data/ilmocplss.gdb
```

This lets tippecanoe automatically reduce feature density at lower zooms, but you have less control over exactly when each layer appears.
