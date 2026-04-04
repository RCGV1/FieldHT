# Xcode Build Optimization Plan


## Project Context

- **Project:** `FieldHT.xcodeproj`
- **Scheme:** `FieldHT`
- **Configuration:** `Debug`
- **Destination:** `platform=iOS Simulator,name=iPhone 16e`
- **Xcode:** Xcode 26.0.1 Build version 17A400
- **macOS:** macOS-26.0.1-arm64-arm-64bit-Mach-O
- **Date:** 2026-04-01T00:42:19.103710+00:00
- **Benchmark artifact:** `.build-benchmark/20260401T004100Z-fieldht.json`

## Baseline Benchmarks

| Metric | Clean | Incremental |
|--------|-------|-------------|
| Median | 11.335s | 1.400s |
| Min | 11.230s | 1.377s |
| Max | 11.532s | 2.044s |
| Runs | 3 | 3 |

### Clean Build Timing Summary

> **Note:** These are aggregated task times across all CPU cores. Because Xcode runs many tasks in parallel, these totals typically exceed the actual build wait time shown above. A large number here does not mean it is blocking your build.

| Category | Tasks | Seconds |
|----------|------:|--------:|
| SwiftCompile | 29 | 28.494s |
| CopyPNGFile | 160 | 5.220s |
| SwiftEmitModule | 3 | 1.851s |
| CompileAssetCatalogVariant | 2 | 1.246s |
| SwiftDriver | 3 | 0.811s |
| Ld | 7 | 0.772s |
| ValidateEmbeddedBinary | 1 | 0.474s |
| ExtractAppIntentsMetadata | 3 | 0.314s |
| CodeSign | 6 | 0.131s |
| AppIntentsSSUTraining | 2 | 0.050s |
| Copy | 14 | 0.026s |
| RegisterExecutionPolicyException | 3 | 0.020s |
| GenerateAssetSymbols | 2 | 0.017s |
| ProcessInfoPlistFile | 2 | 0.014s |
| CopySwiftLibs | 1 | 0.010s |
| WriteAuxiliaryFile | 41 | 0.009s |
| ConstructStubExecutorLinkFileList | 2 | 0.007s |
| ProcessProductPackagingDER | 2 | 0.007s |
| Touch | 2 | 0.003s |
| SwiftDriver Compilation Requirements | 3 | 0.003s |
| LinkAssetCatalog | 2 | 0.003s |
| CpResource | 1 | 0.002s |
| SwiftDriver Compilation | 3 | 0.002s |
| SwiftMergeGeneratedHeaders | 3 | 0.002s |
| ProcessProductPackaging | 2 | 0.001s |
| Validate | 1 | 0.000s |

### Incremental Build Timing Summary

> **Note:** These are aggregated task times across all CPU cores. Because Xcode runs many tasks in parallel, these totals typically exceed the actual build wait time shown above. A large number here does not mean it is blocking your build.

| Category | Tasks | Seconds |
|----------|------:|--------:|
| ValidateEmbeddedBinary | 0 | 0.148s |
| CodeSign | 1 | 0.023s |
| ProcessInfoPlistFile | 2 | 0.014s |
| CopySwiftLibs | 1 | 0.011s |
| Copy | 0 | 0.002s |
| Validate | 0 | 0.000s |

## Build Settings Audit

### Debug Configuration

- [x] `SWIFT_COMPILATION_MODE`: `(unset)` (recommended: `incremental`)
- [x] `SWIFT_OPTIMIZATION_LEVEL`: `-Onone` (recommended: `-Onone`)
- [x] `GCC_OPTIMIZATION_LEVEL`: `0` (recommended: `0`)
- [x] `ONLY_ACTIVE_ARCH`: `YES` (recommended: `YES`)
- [x] `DEBUG_INFORMATION_FORMAT`: `dwarf` (recommended: `dwarf`)
- [x] `ENABLE_TESTABILITY`: `YES` (recommended: `YES`)
- [ ] `EAGER_LINKING`: `(unset)` (recommended: `YES`)

### General (All Configurations)

- [ ] `COMPILATION_CACHING`: `(unset)` (recommended: `YES`)

### Release Configuration

- [x] `SWIFT_COMPILATION_MODE`: `wholemodule` (recommended: `wholemodule`)
- [ ] `SWIFT_OPTIMIZATION_LEVEL`: `(unset)` (recommended: `-O`)
- [ ] `GCC_OPTIMIZATION_LEVEL`: `(unset)` (recommended: `s`)
- [ ] `ONLY_ACTIVE_ARCH`: `(unset)` (recommended: `NO`)
- [x] `DEBUG_INFORMATION_FORMAT`: `dwarf-with-dsym` (recommended: `dwarf-with-dsym`)
- [ ] `ENABLE_TESTABILITY`: `(unset)` (recommended: `NO`)

### Cross-Target Consistency

- [x] `SWIFT_COMPILATION_MODE` is consistent across all targets
- [x] `SWIFT_OPTIMIZATION_LEVEL` is consistent across all targets
- [x] `ONLY_ACTIVE_ARCH` is consistent across all targets
- [x] `DEBUG_INFORMATION_FORMAT` is consistent across all targets

## Compilation Diagnostics

Threshold: 100ms | Total warnings: 0 | Function bodies: 0 | Expressions: 0

No type-checking hotspots found above threshold.

## Prioritized Recommendations

### 1. Set `EAGER_LINKING` to `YES` for Debug

**Category:** build-settings
**Evidence:** Current value: `(unset)`. Allows linker to start before all compilation finishes, reducing wall-clock time.
**Impact:** Medium
**Confidence:** High
**Risk:** Low

### 2. Enable `COMPILATION_CACHING = YES`

**Category:** build-settings
**Evidence:** Current value: `(unset)`. Caches compilation results so repeat builds of unchanged inputs are served from cache. Measured 5-14% faster clean builds across tested projects; benefit compounds during branch switching and pulling changes.
**Impact:** High
**Confidence:** High
**Risk:** Low

### 3. Set `SWIFT_OPTIMIZATION_LEVEL` to `-O` for Release

**Category:** build-settings
**Evidence:** Current value: `(unset)`. Optimized binaries for production (-Osize also acceptable).
**Impact:** Medium
**Confidence:** High
**Risk:** Low

### 4. Set `GCC_OPTIMIZATION_LEVEL` to `s` for Release

**Category:** build-settings
**Evidence:** Current value: `(unset)`. Optimizes C/ObjC for size in release.
**Impact:** Medium
**Confidence:** High
**Risk:** Low

### 5. Set `ONLY_ACTIVE_ARCH` to `NO` for Release

**Category:** build-settings
**Evidence:** Current value: `(unset)`. Release builds must include all architectures for distribution.
**Impact:** Medium
**Confidence:** High
**Risk:** Low

### 6. Set `ENABLE_TESTABILITY` to `NO` for Release

**Category:** build-settings
**Evidence:** Current value: `(unset)`. Removes internal-symbol export overhead from release builds.
**Impact:** Medium
**Confidence:** High
**Risk:** Low


## Approval Checklist

- [ ] **1. Set `EAGER_LINKING` to `YES` for Debug** -- Impact: Medium | Risk: Low
- [ ] **2. Enable `COMPILATION_CACHING = YES`** -- Impact: High | Risk: Low
- [ ] **3. Set `SWIFT_OPTIMIZATION_LEVEL` to `-O` for Release** -- Impact: Medium | Risk: Low
- [ ] **4. Set `GCC_OPTIMIZATION_LEVEL` to `s` for Release** -- Impact: Medium | Risk: Low
- [ ] **5. Set `ONLY_ACTIVE_ARCH` to `NO` for Release** -- Impact: Medium | Risk: Low
- [ ] **6. Set `ENABLE_TESTABILITY` to `NO` for Release** -- Impact: Medium | Risk: Low

## Next Steps

After implementing approved changes, re-benchmark with the same inputs:

```bash
python3 scripts/benchmark_builds.py \
  --project FieldHT.xcodeproj \
  --scheme FieldHT \
  --configuration Debug \
  --destination "platform=iOS Simulator,name=iPhone 16e" \
  --output-dir .build-benchmark
```

Compare the new wall-clock medians against the baseline. Report results as:
"Your [clean/incremental] build now takes X.Xs (was Y.Ys) -- Z.Zs faster/slower."
