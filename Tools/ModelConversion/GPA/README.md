# GPA GUI Detector conversion

This tool downloads the pinned `Salesforce/GPA-GUI-Detector` checkpoint and exports a
Vision-compatible Core ML package with embedded non-maximum suppression.

Enter the project development shell and run:

```sh
nix develop
python Tools/ModelConversion/GPA/convert.py
```

`requirements.txt` pins the direct conversion dependencies and `requirements.lock` pins the full
transitive environment. The Nix shell creates `.venv` and synchronizes it from the lock file.

The default output is `Models/Generated/GPA_GUI_Detector.mlpackage`. Compare exports at 640, 960,
and 1280 before selecting the production input size:

```sh
python Tools/ModelConversion/GPA/convert.py \
  --image-size 640 \
  --output Models/Generated/GPA_GUI_Detector_640.mlpackage
```

The source checkpoint and generated packages are intentionally ignored by Git. After validating an
export, copy it to `Resources/Models/GPA_GUI_Detector.mlpackage` and add that package to the OmniVim
app target's Copy Bundle Resources phase. Xcode compiles it to `GPA_GUI_Detector.mlmodelc`.

Development builds also look for `Models/Generated/GPA_GUI_Detector.mlpackage`, so Telegram can use
the freshly converted model without changing the Xcode resource phase. Set `OMNIVIM_GPA_MODEL_PATH`
to test a model at another location. Distribution builds should bundle the compiled model.

The checkpoint is pinned to Hugging Face revision
`d04be6b715acb517068ca15d4b79159d26292713`. The model card declares the checkpoint MIT-licensed;
retain its provenance and review the Ultralytics exporter/runtime licensing before distribution.
