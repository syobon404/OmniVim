import AppKit

struct AXCapabilityProbe: ApplicationCapabilityProbing {
    let safetyLevel = ProbeSafetyLevel.passive

    func probe(
        context: RunningApplicationContext,
        fingerprint: ApplicationFingerprint
    ) -> ApplicationCapabilityReport {
        guard AXIsProcessTrusted() else {
            return ApplicationCapabilityReport(
                fingerprint: fingerprint,
                evidence: [evidence(
                    .accessibilityTrusted,
                    status: .unsupported,
                    method: "AXIsProcessTrusted"
                )]
            )
        }

        let application = context.accessibilityElement
        let focused = focusedElement(in: application)
        var result = [evidence(
            .accessibilityTrusted,
            status: .confirmed,
            method: "AXIsProcessTrusted"
        )]
        result.append(evidence(
            .focusedElement,
            status: supportStatus(for: focused.error, hasValue: focused.element != nil),
            method: "AXFocusedUIElement",
            error: focused.error
        ))

        let target = focused.element ?? application
        let attributeResult = attributeNames(of: target)
        let attributes = Set(attributeResult.names)
        let actionResult = actionNames(of: target)
        result.append(evidence(
            .actionNames,
            status: supportStatus(for: actionResult.error, hasValue: !actionResult.names.isEmpty),
            method: "AXUIElementCopyActionNames",
            error: actionResult.error,
            detail: "count=\(actionResult.names.count)"
        ))

        let parameterizedResult = parameterizedAttributeNames(of: target)
        result.append(evidence(
            .parameterizedAttributes,
            status: supportStatus(
                for: parameterizedResult.error,
                hasValue: !parameterizedResult.names.isEmpty
            ),
            method: "AXUIElementCopyParameterizedAttributeNames",
            error: parameterizedResult.error,
            detail: "count=\(parameterizedResult.names.count)"
        ))

        let role = stringAttribute(kAXRoleAttribute as String, of: target)
        let editable = boolAttribute("AXIsEditable", of: target)
        let editableRole = AXEditableRolePolicy.accepts(
            role: role,
            isEditable: editable,
            allowsInference: true
        )
        result.append(evidence(
            .editableRole,
            status: editableRole ? .confirmed : .unsupported,
            method: "AXRole+AXIsEditable",
            detail: role.map { "role=\($0)" }
        ))

        let selectedRangeNames: Set<String> = [
            kAXSelectedTextRangeAttribute as String,
            "AXSelectedTextMarkerRange"
        ]
        result.append(evidence(
            .selectedTextRange,
            status: attributes.isDisjoint(with: selectedRangeNames) ? .unsupported : .confirmed,
            method: "AXAttributeNames",
            error: attributeResult.error
        ))

        let markerNames = Set(parameterizedResult.names + attributeResult.names)
        result.append(evidence(
            .textMarkers,
            status: markerNames.contains(where: { $0.localizedCaseInsensitiveContains("TextMarker") })
                ? .confirmed
                : .unsupported,
            method: "AXAttributeNames+AXParameterizedAttributeNames"
        ))

        let hitTest = hitTestFocusedElement(focused.element, in: application)
        result.append(evidence(
            .hitTesting,
            status: supportStatus(for: hitTest.error, hasValue: hitTest.element != nil),
            method: "AXUIElementCopyElementAtPosition",
            error: hitTest.error
        ))

        var observer: AXObserver?
        let observerError = AXObserverCreate(context.processIdentifier, { _, _, _, _ in }, &observer)
        result.append(evidence(
            .notificationObserver,
            status: supportStatus(for: observerError, hasValue: observer != nil),
            method: "AXObserverCreate",
            error: observerError
        ))

        var settable = DarwinBoolean(false)
        let manualAccessibilityError = AXUIElementIsAttributeSettable(
            application,
            "AXManualAccessibility" as CFString,
            &settable
        )
        result.append(evidence(
            .electronManualAccessibility,
            status: manualAccessibilityError == .success && settable.boolValue
                ? .confirmed
                : .unsupported,
            method: "AXUIElementIsAttributeSettable",
            error: manualAccessibilityError
        ))

        return ApplicationCapabilityReport(fingerprint: fingerprint, evidence: result)
    }

    private func focusedElement(in application: AXUIElement) -> (error: AXError, element: AXUIElement?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard error == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return (error, nil) }
        return (error, (value as! AXUIElement))
    }

    private func attributeNames(of element: AXUIElement) -> (error: AXError, names: [String]) {
        var names: CFArray?
        let error = AXUIElementCopyAttributeNames(element, &names)
        return (error, (names as? [String]) ?? [])
    }

    private func actionNames(of element: AXUIElement) -> (error: AXError, names: [String]) {
        var names: CFArray?
        let error = AXUIElementCopyActionNames(element, &names)
        return (error, (names as? [String]) ?? [])
    }

    private func parameterizedAttributeNames(
        of element: AXUIElement
    ) -> (error: AXError, names: [String]) {
        var names: CFArray?
        let error = AXUIElementCopyParameterizedAttributeNames(element, &names)
        return (error, (names as? [String]) ?? [])
    }

    private func hitTestFocusedElement(
        _ focusedElement: AXUIElement?,
        in application: AXUIElement
    ) -> (error: AXError, element: AXUIElement?) {
        guard let focusedElement, let frame = frame(of: focusedElement) else {
            return (.noValue, nil)
        }
        var element: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(
            application,
            Float(frame.midX),
            Float(frame.midY),
            &element
        )
        return (error, element)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        AXEditorResolver().frame(of: element)
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func boolAttribute(_ name: String, of element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return false
        }
        return (value as? NSNumber)?.boolValue == true
    }

    private func supportStatus(for error: AXError, hasValue: Bool) -> CapabilitySupportStatus {
        if error == .success { return hasValue ? .confirmed : .unsupported }
        if error == .attributeUnsupported || error == .notImplemented || error == .actionUnsupported {
            return .unsupported
        }
        return .inconclusive
    }

    private func evidence(
        _ capability: CapabilityID,
        status: CapabilitySupportStatus,
        method: String,
        error: AXError? = nil,
        detail: String? = nil
    ) -> ProbeEvidence {
        ProbeEvidence(
            capability: capability,
            status: status,
            safetyLevel: safetyLevel,
            method: method,
            errorCode: error.map { Int($0.rawValue) },
            detail: detail,
            capturedAt: Date()
        )
    }
}
