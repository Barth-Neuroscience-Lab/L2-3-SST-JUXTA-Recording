// ============================================================
// MULTI-STACK SAFE — MANUAL NEUROPIL FINETUNE VERSION
// 3-channel soma / neuropil extraction + QC crop PNG
//
// PURPOSE:
//   This version DOES NOT generate, enlarge, XOR, delete, add,
//   rename, or otherwise modify neuropil ROIs.
//
//   It is intended to run AFTER the original macro has generated
//   neuropil ROIs and you have manually adjusted/reassigned them
//   in ROI Manager as needed.
//
// REQUIRED ROI NAMING:
//   Soma ROI:
//       source_image_title@@cell_name
//
//   Matching neuropil ROI:
//       source_image_title@@cell_name_neuropil
//
//   Example pair:
//       sample_A.tif@@cell1
//       sample_A.tif@@cell1_neuropil
//
//   The source image title must match the OPEN ImageJ/Fiji window
//   title exactly.
//
//   This macro NEVER guesses the source image or neuropil pairing.
//   Missing, duplicated, untagged, or invalid ROI pairs are SKIPPED.
//
// CSV:
//   source,cell,z,region,x,y,CH1,CH2,CH3
//
// PNG (WC_MODE = false):
//   CH1 red | CH2 green | CH1+CH2 | CH1+CH2+outlines
// PNG (WC_MODE = true):
//   CH1 green | CH3 magenta | CH1+CH3 | CH1+CH3+outlines
//
// ============================================================

requires("1.53v");

DELIMITER = "@@";
WC_MODE = true;  // false = CH1 red + CH2 green; true = CH1 green + CH3 magenta
SOMA_COLOR = "white";
NEUROPIL_COLOR = "blue";
OUTLINE_WIDTH = 1;


// ------------------------------------------------------------
// Basic checks
// ------------------------------------------------------------

titles = getList("image.titles");

if (titles.length == 0)
    exit("No images are open.");

if (roiManager("count") == 0)
    exit("ROI Manager is empty.");

originalImageID = getImageID();


// ------------------------------------------------------------
// Ask for CSV destination
// ROI Manager is NOT modified by this macro.
// ------------------------------------------------------------

out = File.open("");

csvDir  = File.directory;
csvName = File.name;

if (!endsWith(csvDir, File.separator))
    csvDir = csvDir + File.separator;

csvBase = File.getNameWithoutExtension(csvName);
cropDir = csvDir + csvBase + "_crops" + File.separator;

File.makeDirectory(cropDir);

print(out, "source,cell,z,region,x,y,CH1,CH2,CH3");


// Never show all mixed-image ROIs on one image.
roiManager("show none");


// ------------------------------------------------------------
// Count soma candidates.
// Any ROI whose name ends with "_neuropil" is treated as neuropil.
// Everything else is treated as a soma candidate.
// ------------------------------------------------------------

nRoi = roiManager("count");
nSoma = 0;

for (q = 0; q < nRoi; q++) {
    candidateName = RoiManager.getName(q);
    if (!endsWith(candidateName, "_neuropil"))
        nSoma++;
}

if (nSoma == 0)
    exit("No soma ROIs found. Soma ROI names must not end with '_neuropil'.");

processed = 0;
somaSeen = 0;
skippedUntagged = 0;
skippedMissingNeuropil = 0;
skippedDuplicateNeuropil = 0;
skippedMissingImage = 0;
skippedInvalid = 0;


// ============================================================
// MAIN LOOP
// ============================================================

for (i = 0; i < nRoi; i++) {

    fullName = RoiManager.getName(i);

    // Existing neuropil ROIs are consumed as partners, not as somas.
    if (endsWith(fullName, "_neuropil"))
        continue;

    somaSeen++;
    showProgress(somaSeen, nSoma);


    // --------------------------------------------------------
    // Parse source title and cell name from soma ROI
    // --------------------------------------------------------

    sep = indexOf(fullName, DELIMITER);

    if (sep < 1) {
        print("WARNING: skipped soma ROI '" + fullName +
              "' because it has no source-image tag. Expected: sourceTitle@@cellName");
        skippedUntagged++;
        continue;
    }

    sourceTitle = substring(fullName, 0, sep);
    cell = substring(fullName, sep + lengthOf(DELIMITER));

    if (lengthOf(cell) == 0)
        cell = "roi" + (i + 1);


    // --------------------------------------------------------
    // Find the EXISTING matching neuropil ROI by exact name
    // --------------------------------------------------------

    neuropilName = fullName + "_neuropil";
    neuropilIndex = -1;
    neuropilMatches = 0;

    for (q = 0; q < nRoi; q++) {
        if (RoiManager.getName(q) == neuropilName) {
            neuropilIndex = q;
            neuropilMatches++;
        }
    }

    if (neuropilMatches == 0) {
        print("WARNING: skipped '" + fullName +
              "' because matching neuropil ROI was not found: " + neuropilName);
        skippedMissingNeuropil++;
        continue;
    }

    if (neuropilMatches > 1) {
        print("WARNING: skipped '" + fullName +
              "' because more than one ROI has the matching neuropil name: " + neuropilName);
        skippedDuplicateNeuropil++;
        continue;
    }


    // --------------------------------------------------------
    // Find the EXACT source image by its open window title
    // --------------------------------------------------------

    sourceID = findOpenImageID(sourceTitle);

    if (sourceID == 0) {
        print("WARNING: skipped '" + fullName +
              "' because source image is not open: " + sourceTitle);
        skippedMissingImage++;
        continue;
    }

    selectImage(sourceID);

    getDimensions(imgW, imgH, nC, nZ, nT);

    if (nC != 3) {
        print("WARNING: skipped '" + fullName +
              "' because '" + sourceTitle +
              "' has " + nC + " channels instead of 3.");
        skippedInvalid++;
        continue;
    }

    if (nT != 1) {
        print("WARNING: skipped '" + fullName +
              "' because '" + sourceTitle +
              "' has T=" + nT + " instead of T=1.");
        skippedInvalid++;
        continue;
    }


    // --------------------------------------------------------
    // Validate soma ROI ON ITS CORRECT SOURCE IMAGE
    // --------------------------------------------------------

    roiManager("select", i);

    Roi.getPosition(c, z, t);

    type = selectionType();

    // rectangle, oval, polygon, freehand, traced, composite
    validArea = (type >= 0 && type <= 4) || type == 9;

    if (z == 0) {
        print("WARNING: skipped '" + fullName +
              "' because soma ROI has no stored Z position.");
        skippedInvalid++;
        continue;
    }

    if (z < 1 || z > nZ) {
        print("WARNING: skipped '" + fullName +
              "' because soma ROI Z=" + z +
              " is outside source stack Z=1.." + nZ + ".");
        skippedInvalid++;
        continue;
    }

    if (!validArea) {
        print("WARNING: skipped '" + fullName +
              "' because soma ROI is not an area ROI.");
        skippedInvalid++;
        continue;
    }


    // --------------------------------------------------------
    // Validate EXISTING neuropil ROI
    // --------------------------------------------------------

    roiManager("select", neuropilIndex);

    Roi.getPosition(nc, nz, nt);

    neuropilType = selectionType();
    validNeuropilArea =
        (neuropilType >= 0 && neuropilType <= 4) || neuropilType == 9;

    if (!validNeuropilArea) {
        print("WARNING: skipped '" + fullName +
              "' because matching neuropil ROI is not an area ROI: " + neuropilName);
        skippedInvalid++;
        continue;
    }

    // A manually reassigned neuropil may have no stored Z (nz == 0),
    // or its stored Z metadata may change during manual ROI reassignment.
    // The ROI geometry is accepted as supplied; extraction always uses
    // the soma ROI's stored Z, matching the downstream behavior of the
    // original macro. A mismatch is reported only as a note.
    if (nz != 0 && nz != z) {
        print("NOTE: '" + fullName +
              "' has soma Z=" + z +
              " and neuropil ROI stored Z=" + nz +
              "; using soma Z=" + z + " for both pixel extractions.");
    }


    // Precision is determined from THIS source image.
    if (bitDepth() == 32)
        decimals = 9;
    else
        decimals = 0;


    // --------------------------------------------------------
    // Report existing soma / neuropil geometry
    // --------------------------------------------------------

    roiManager("select", i);
    getSelectionBounds(x0, y0, rw, rh);

    roiManager("select", neuropilIndex);
    getSelectionBounds(nx0, ny0, nrw, nrh);

    print(
        "SOURCE=" + sourceTitle +
        " | CELL=" + cell +
        " | Z=" + z +
        " | soma bbox=" + rw + "x" + rh +
        " px | existing neuropil bbox=" + nrw + "x" + nrh + " px"
    );


    // --------------------------------------------------------
    // Export raw pixel values FROM THIS SOURCE IMAGE
    // --------------------------------------------------------

    exportPixels(
        out,
        sourceID,
        i,
        sourceTitle,
        cell,
        z,
        "soma",
        decimals
    );

    exportPixels(
        out,
        sourceID,
        neuropilIndex,
        sourceTitle,
        cell,
        z,
        "neuropil",
        decimals
    );


    // --------------------------------------------------------
    // Save QC crop FROM THIS SOURCE IMAGE
    // --------------------------------------------------------

    saveCellCrop(
        sourceID,
        i,
        neuropilIndex,
        sourceTitle,
        cell,
        z,
        imgW,
        imgH,
        cropDir,
        SOMA_COLOR,
        NEUROPIL_COLOR,
        OUTLINE_WIDTH,
        WC_MODE
    );


    processed++;
}


// ============================================================
// FINISH
// ============================================================

File.close(out);

roiManager("show none");

// Return to image that was active when macro started.
selectImage(originalImageID);

showMessage(
    "Done — manual neuropil finetune",
    processed + " soma/neuropil pair(s) processed.\n\n" +
    "Skipped untagged soma: " + skippedUntagged + "\n" +
    "Skipped missing neuropil: " + skippedMissingNeuropil + "\n" +
    "Skipped duplicate neuropil name: " + skippedDuplicateNeuropil + "\n" +
    "Skipped missing source image: " + skippedMissingImage + "\n" +
    "Skipped invalid ROI/image: " + skippedInvalid + "\n\n" +
    "Pixel CSV:\n" +
    csvDir + csvName + "\n\n" +
    "Crop PNG folder:\n" +
    cropDir + "\n\n" +
    "ROI Manager was not modified. Existing neuropil ROIs were used exactly as supplied."
);



// ============================================================
// Find an open image using an EXACT ImageJ window title.
// Returns image ID, or 0 if not found.
// ============================================================

function findOpenImageID(title) {

    openTitles = getList("image.titles");

    for (q = 0; q < openTitles.length; q++) {

        if (openTitles[q] == title) {
            selectWindow(title);
            return getImageID();
        }
    }

    return 0;
}



// ============================================================
// Export every pixel inside ROI
// ============================================================

function exportPixels(
    out,
    sourceID,
    roiIndex,
    sourceTitle,
    cell,
    z,
    region,
    decimals
) {

    selectImage(sourceID);
    roiManager("select", roiIndex);

    Roi.getContainedPoints(xs, ys);

    n = xs.length;

    ch1 = newArray(n);
    ch2 = newArray(n);
    ch3 = newArray(n);


    Stack.setPosition(1, z, 1);
    for (p = 0; p < n; p++)
        ch1[p] = getPixel(xs[p], ys[p]);


    Stack.setPosition(2, z, 1);
    for (p = 0; p < n; p++)
        ch2[p] = getPixel(xs[p], ys[p]);


    Stack.setPosition(3, z, 1);
    for (p = 0; p < n; p++)
        ch3[p] = getPixel(xs[p], ys[p]);


    for (p = 0; p < n; p++) {

        print(
            out,
            "\"" + sourceTitle + "\"," +
            "\"" + cell + "\"," +
            z + "," +
            region + "," +
            xs[p] + "," +
            ys[p] + "," +
            d2s(ch1[p], decimals) + "," +
            d2s(ch2[p], decimals) + "," +
            d2s(ch3[p], decimals)
        );
    }
}



// ============================================================
// Generate 4-panel PNG
// ============================================================

function saveCellCrop(
    sourceID,
    somaIndex,
    neuropilIndex,
    sourceTitle,
    cell,
    z,
    imgW,
    imgH,
    cropDir,
    somaColor,
    neuropilColor,
    outlineWidth,
    wcMode
) {

    selectImage(sourceID);
    roiManager("select", somaIndex);

    getSelectionBounds(x0, y0, rw, rh);


    side = 2 * maxOf(rw, rh);

    desiredW = side;
    desiredH = side;

    cx = x0 + rw / 2;
    cy = y0 + rh / 2;

    desiredX = round(cx - desiredW / 2);
    desiredY = round(cy - desiredH / 2);

    x1 = desiredX;
    y1 = desiredY;

    x2 = desiredX + desiredW;
    y2 = desiredY + desiredH;


    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x2 > imgW) x2 = imgW;
    if (y2 > imgH) y2 = imgH;

    cw = x2 - x1;
    ch = y2 - y1;


    if (cw <= 0 || ch <= 0) {
        print("WARNING: crop failed for " + sourceTitle + " / " + cell);
        return;
    }


    // Display scaling only. Raw CSV measurements are unchanged.
    // Standard mode: CH1 red + CH2 green.
    // WC mode: CH1 green + CH3 magenta.
    channelA = 1;
    if (wcMode)
        channelB = 3;
    else
        channelB = 2;

    selectImage(sourceID);
    makeRectangle(x1, y1, cw, ch);

    Stack.setPosition(channelA, z, 1);
    getRawStatistics(nPixelsA, meanA, minA, maxA);

    Stack.setPosition(channelB, z, 1);
    getRawStatistics(nPixelsB, meanB, minB, maxB);

    n = cw * ch;
    pixelsA = newArray(n);
    pixelsB = newArray(n);

    Stack.setPosition(channelA, z, 1);
    k = 0;
    for (yy = 0; yy < ch; yy++) {
        for (xx = 0; xx < cw; xx++) {
            raw = getPixel(x1 + xx, y1 + yy);
            pixelsA[k] = scaleTo8(raw, minA, maxA);
            k++;
        }
    }

    Stack.setPosition(channelB, z, 1);
    k = 0;
    for (yy = 0; yy < ch; yy++) {
        for (xx = 0; xx < cw; xx++) {
            raw = getPixel(x1 + xx, y1 + yy);
            pixelsB[k] = scaleTo8(raw, minB, maxB);
            k++;
        }
    }

    newImage(
        "__cell_crop__",
        "RGB black",
        4 * cw,
        ch,
        1
    );

    cropID = getImageID();
    k = 0;

    for (yy = 0; yy < ch; yy++) {
        for (xx = 0; xx < cw; xx++) {
            a = pixelsA[k];
            b = pixelsB[k];

            if (wcMode) {
                // CH1 green, CH3 magenta (red + blue).
                rgbA = a * 256;
                rgbB = b * 65536 + b;
                mergeRGB = b * 65536 + a * 256 + b;
            } else {
                // CH1 red, CH2 green.
                rgbA = a * 65536;
                rgbB = b * 256;
                mergeRGB = a * 65536 + b * 256;
            }

            setPixel(xx,          yy, rgbA);
            setPixel(cw + xx,     yy, rgbB);
            setPixel(2 * cw + xx, yy, mergeRGB);
            setPixel(3 * cw + xx, yy, mergeRGB);
            k++;
        }
    }


    // Neuropil first.
    selectImage(sourceID);
    roiManager("select", neuropilIndex);
    Roi.copy();

    selectImage(cropID);
    Roi.paste();
    Roi.setPosition(0, 0, 0);
    Roi.translate(3 * cw - x1, -y1);
    Overlay.addSelection(neuropilColor, outlineWidth);
    run("Select None");


    // Soma second.
    selectImage(sourceID);
    roiManager("select", somaIndex);
    Roi.copy();

    selectImage(cropID);
    Roi.paste();
    Roi.setPosition(0, 0, 0);
    Roi.translate(3 * cw - x1, -y1);
    Overlay.addSelection(somaColor, outlineWidth);
    run("Select None");


    Overlay.show;
    Overlay.flatten;

    safeSource = safeFileName(sourceTitle);
    safeCell   = safeFileName(cell);

    saveAs(
        "PNG",
        cropDir + safeSource + "__" + safeCell + "_crop.png"
    );

    close();

    selectImage(cropID);
    close();
}



// ============================================================
// Filename-safe text
// ============================================================

function safeFileName(s) {
    return replace(s, "[^A-Za-z0-9._-]", "_");
}



// ============================================================
// Per-crop linear min-max scaling to 8-bit display
// ============================================================

function scaleTo8(value, minValue, maxValue) {

    if (maxValue <= minValue)
        return 0;

    v =
        round(
            255 *
            (value - minValue) /
            (maxValue - minValue)
        );

    if (v < 0) v = 0;
    if (v > 255) v = 255;

    return v;
}
