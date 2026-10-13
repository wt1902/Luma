#!/usr/bin/env python3
"""Post-generation fix for XcodeGen issue #1549: XcodeGen does not link
XCSwiftPackageProductDependency entries to local (path-based) Swift packages,
which makes the Xcode GUI report "Missing package product". This script
attaches the MartinOMEMO product dependencies to the vendored local package
reference in the generated project file.

Run after every `xcodegen generate` (see the Makefile `project` target).
"""
import sys

PBXPROJ = "Luma.xcodeproj/project.pbxproj"


def main() -> int:
    with open(PBXPROJ, encoding="utf-8") as handle:
        text = handle.read()

    # Find the object id of the local package reference.
    ref_id = None
    for line in text.splitlines():
        marker = " /* XCLocalSwiftPackageReference \"ThirdParty/MartinOMEMO\" */ = {"
        if marker in line:
            ref_id = line.split(" /*")[0].strip()
            break
    if ref_id is None:
        print("patch-xcodeproj: local package reference not found; nothing to do")
        return 0

    needle = (
        "/* MartinOMEMO */ = {\n"
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        "\t\t\tproductName = MartinOMEMO;"
    )
    patch = (
        "/* MartinOMEMO */ = {\n"
        "\t\t\tisa = XCSwiftPackageProductDependency;\n"
        "\t\t\tpackage = " + ref_id + " /* XCLocalSwiftPackageReference \"ThirdParty/MartinOMEMO\" */;\n"
        "\t\t\tproductName = MartinOMEMO;"
    )

    count = text.count(needle)
    if count == 0:
        print("patch-xcodeproj: MartinOMEMO product dependencies already linked")
        return 0
    patched = text.replace(needle, patch)
    with open(PBXPROJ, "w", encoding="utf-8") as handle:
        handle.write(patched)
    print("patch-xcodeproj: linked " + str(count) + " MartinOMEMO product dependencies")
    return 0


if __name__ == "__main__":
    sys.exit(main())
