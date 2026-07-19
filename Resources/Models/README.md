# Runtime models

Validated Core ML packages used by the Xcode app target belong here. The checked-in
`GPA_GUI_Detector.mlpackage` lets a fresh clone build and run without Python or model conversion.

The conversion tool writes maintainer experiments to `Models/Generated`. After validating a new
export, promote it with:

```sh
./scripts/promote-gpa-model.sh
```

Review the changed runtime model and attribution before committing it. Xcode compiles the package
into `GPA_GUI_Detector.mlmodelc` and embeds that compiled model in the application bundle.
