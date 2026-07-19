# Runtime models

Validated Core ML packages used by the Xcode app target belong here. The GPA conversion tool writes
experimental exports to `Models/Generated`; promote a validated export with:

```sh
./scripts/promote-gpa-model.sh
```

The promoted package remains ignored because it is a generated 39 MB artifact. Xcode compiles it
into `GPA_GUI_Detector.mlmodelc` and embeds that compiled model in the application bundle.
