# Dataset placement

Download the data separately: **[TODO: archive URL/DOI, dataset version, archive sizes, and checksums]**.

Extract the archives here, retaining their internal names. The two `PLACEHOLDER_*` directories are instruction markers; the loaders expect the names without `PLACEHOLDER_`:

| Dataset | Required destination |
| --- | --- |
| Juxtacellular/whole-cell recordings | `ingredients/PassivePuff_JuxtaCellular_FromJS_202509/` |
| High-frequency calcium imaging | `ingredients/PassivePuff_HighFreqImaging/` |

With `RATATOUILLE_DATA_PATH` set, substitute that directory for `ingredients/`.

## Electrophysiology archive

- Retain the cohort directories (`SST_JUX`, `SST_WC`, `PV_JUX`, `PYR_JUX`, and `PYR_WC` where used).
- Include the `*_datafile.pkl` recordings. The default loader reads pandas pickles containing the `mouse`, `filename`, `start_exp`, `end_exp`, `airpuff`, `stim_time`, `cam`, `Vm1`, and `vm_time` entries. The `filename` value is split into day, cell, and session identifiers at underscores.
- Include the saved `spike_waveform_curation.pkl` selections at their original relative paths. Missing files trigger interactive curation.
- Include `sst_whole_cell_staining/` CSVs if the whole-cell staining analysis is part of the release.

## Calcium-imaging archive

- Retain `HighFreqImaging_Combine_ROIs/<mouse_id>/<date_FOV_or_ROI_id>/`.
- Include `TIMELINE_*.csv`, Suite2p `Fall.mat` exports, and the corresponding MES-derived `INFO_*.xlsx` files. The `default_two_photon_mes_parser` recipe uses these together to align frames with the timeline.
- Include matching behavioral CSVs and saved whisker/pupil/ROI measurements used by the analyses. Keep the archive's names and relative paths so users can reuse the measurements without redoing interactive extraction.
- Include `HighFreqImaging_Combine_ROIs_info/<mouse_id>/` with staining CSVs and `*_crop.png` previews for posthoc staining assignment and state-dependent analyses.
- Raw MES files, TIFFs, videos, Suite2p `ops.npy`.
