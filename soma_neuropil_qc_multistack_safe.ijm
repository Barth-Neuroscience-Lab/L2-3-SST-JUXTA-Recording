// ============================================================
// MULTI-STACK SAFE
// 3-channel soma / neuropil extraction + QC crop PNG
//
// WC_MODE = false:
//   panel 1 = CH1 (red)
//   panel 2 = CH2 (green)
//   panel 3 = CH1 + CH2
//   panel 4 = CH1 + CH2 + soma/neuropil outlines
//
// WC_MODE = true:
//   panel 1 = CH1 (green)
//   panel 2 = CH3 (magenta)
//   panel 3 = CH1 + CH3
//   panel 4 = CH1 + CH3 + soma/neuropil outlines
//
// ROI names must contain their exact source window title:
//     source_image_title@@cell_name
//
// CSV columns always contain RAW CH1, CH2 and CH3 values:
//   source,cell,z,region,x,y,CH1,CH2,CH3
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
// Ask for CSV destination BEFORE modifying ROI Manager
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
// Delete OLD generated neuropil ROIs only
// ------------------------------------------------------------

for (i = roiManager("count") - 1; i >= 0; i--) {
    name = RoiManager.getName(i);

    if (endsWith(name, "_neuropil")) {
        roiManager("select", i);
        roiManager("delete");
    }
}

// Everything now remaining is treated as a soma candidate.
nSoma = roiManager("count");

if (nSoma == 0)
    exit("No soma ROIs found.");

processed = 0;
skippedUntagged = 0;
skippedMissingImage = 0;
skippedInvalid = 0;

// ============================================================
// MAIN LOOP
// ============================================================

for (i = 0; i < nSoma; i++) {
    fullName = RoiManager.getName(i);

    // --------------------------------------------------------
    // Parse source title and cell name
    // --------------------------------------------------------

    sep = indexOf(fullName, DELIMITER);

    if (sep < 1) {
        print("WARNING: skipped ROI '" + fullName +
              "' because it has no source-image tag. Expected: sourceTitle@@cellName");
        skippedUntagged++;
        continue;
    }

    sourceTitle = substring(fullName, 0, sep);
    cell = substring(fullName, sep + lengthOf(DELIMITER));

    if (lengthOf(cell) == 0)
        cell = "roi" + (i + 1);

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
    // Activate this ROI ON ITS CORRECT SOURCE IMAGE
    // --------------------------------------------------------

    roiManager("select", i);
    Roi.getPosition(c, z, t);
    type = selectionType();

    // rectangle, oval, polygon, freehand, traced, composite
    validArea = (type >= 0 && type <= 4) || type == 9;

    if (z == 0) {
        print("WARNING: skipped '" + fullName +
              "' because ROI has no stored Z position.");
        skippedInvalid++;
        continue;
    }

    if (z < 1 || z > nZ) {
        print("WARNING: skipped '" + fullName +
              "' because ROI Z=" + z +
              " is outside source stack Z=1.." + nZ + ".");
        skippedInvalid++;
        continue;
    }

    if (!validArea) {
        print("WARNING: skipped '" + fullName +
              "' because it is not an area ROI.");
        skippedInvalid++;
        continue;
    }

    // Precision is determined from THIS source image.
    if (bitDepth() == 32)
        decimals = 9;
    else
        decimals = 0;

    // --------------------------------------------------------
    // Soma bounding box
    // --------------------------------------------------------

    getSelectionBounds(x0, y0, rw, rh);

    // --------------------------------------------------------
    // Neuropil expansion
    // --------------------------------------------------------

    band = round((rw + rh) / 8);
    if (band < 1)
        band = 1;

    print(
        "SOURCE=" + sourceTitle +
        " | CELL=" + cell +
        " | Z=" + z +
        " | soma bbox=" + rw + "x" + rh +
        " px | neuropil band=" + band + " px"
    );

    // --------------------------------------------------------
    // Generate expanded ROI on the CORRECT source image
    // --------------------------------------------------------

    run("Enlarge...", "enlarge=" + band + " pixel");
    roiManager("add");
    tempIndex = roiManager("count") - 1;

    // --------------------------------------------------------
    // XOR(expanded, soma) = neuropil ring
    // --------------------------------------------------------

    pair = newArray(i, tempIndex);
    roiManager("select", pair);
    roiManager("xor");
    Roi.setPosition(0, z, 0);

    roiManager("add");
    neuropilIndex = roiManager("count") - 1;

    roiManager("select", neuropilIndex);
    roiManager("rename", fullName + "_neuropil");

    // Remove temporary expanded ROI.
    roiManager("select", tempIndex);
    roiManager("delete");
    neuropilIndex = roiManager("count") - 1;

    // --------------------------------------------------------
    // Export raw pixel values FROM THIS SOURCE IMAGE
    // --------------------------------------------------------

    exportPixels(out, sourceID, i, sourceTitle, cell, z, "soma", decimals);
    exportPixels(out, sourceID, neuropilIndex, sourceTitle, cell, z, "neuropil", decimals);

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
    showProgress(i + 1, nSoma);
}

// ============================================================
// FINISH
// ============================================================

File.close(out);
roiManager("show none");

// Return to image that was active when macro started.
selectImage(originalImageID);

showMessage(
    "Done",
    processed + " soma ROI(s) processed.\n\n" +
    "Skipped untagged: " + skippedUntagged + "\n" +
    "Skipped missing source image: " + skippedMissingImage + "\n" +
    "Skipped invalid ROI/image: " + skippedInvalid + "\n\n" +
    "Pixel CSV:\n" + csvDir + csvName + "\n\n" +
    "Crop PNG folder:\n" + cropDir + "\n\n" +
    "ROI Manager overlays were left OFF intentionally because ROIs belong to multiple source images."
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
// Export every pixel inside ROI (always CH1, CH2, CH3)
// ============================================================

function exportPixels(out, sourceID, roiIndex, sourceTitle, cell, z, region, decimals) {
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
            z + "," + region + "," +
            xs[p] + "," + ys[p] + "," +
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

    // Choose which raw channels to display. CSV remains unchanged.
    channelA = 1;
    if (wcMode)
        channelB = 3;
    else
        channelB = 2;

    // Independent per-crop scaling of each displayed channel.
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

    newImage("__cell_crop__", "RGB black", 4 * cw, ch, 1);
    cropID = getImageID();

    k = 0;
    for (yy = 0; yy < ch; yy++) {
        for (xx = 0; xx < cw; xx++) {
            a = pixelsA[k];
            b = pixelsB[k];

            if (wcMode) {
                // CH1 green; CH3 magenta = red + blue.
                rgbA = a * 256;
                rgbB = b * 65536 + b;
                mergeRGB = b * 65536 + a * 256 + b;
            } else {
                // CH1 red; CH2 green.
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

    // Neuropil first: outline on panel 4 only.
    selectImage(sourceID);
    roiManager("select", neuropilIndex);
    Roi.copy();

    selectImage(cropID);
    Roi.paste();
    Roi.setPosition(0, 0, 0);
    Roi.translate(3 * cw - x1, -y1);
    Overlay.addSelection(neuropilColor, outlineWidth);
    run("Select None");

    // Soma second: outline on panel 4 only.
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
    safeCell = safeFileName(cell);

    saveAs("PNG", cropDir + safeSource + "__" + safeCell + "_crop.png");
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

    v = round(255 * (value - minValue) / (maxValue - minValue));

    if (v < 0) v = 0;
    if (v > 255) v = 255;

    return v;
}
