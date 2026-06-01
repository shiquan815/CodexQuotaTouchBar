#import <Cocoa/Cocoa.h>

static NSBezierPath *RoundedRect(NSRect rect, CGFloat radius) {
    return [NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius];
}

static void DrawGradientRing(NSRect rect, CGFloat width) {
    NSBezierPath *outer = RoundedRect(rect, rect.size.width * 0.20);
    NSBezierPath *inner = RoundedRect(NSInsetRect(rect, width, width), (rect.size.width - width * 2.0) * 0.18);
    [outer appendBezierPath:inner];
    outer.windingRule = NSWindingRuleEvenOdd;

    [NSGraphicsContext saveGraphicsState];
    [outer addClip];
    NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
        [NSColor colorWithCalibratedRed:1.00 green:0.18 blue:0.12 alpha:1.0],
        [NSColor colorWithCalibratedRed:1.00 green:0.82 blue:0.16 alpha:1.0],
        [NSColor colorWithCalibratedRed:0.30 green:0.96 blue:0.18 alpha:1.0]
    ]];
    [gradient drawInRect:rect angle:0.0];
    [NSGraphicsContext restoreGraphicsState];
}

static void DrawFallbackMark(NSRect rect) {
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:rect];
    [[NSColor colorWithCalibratedRed:0.10 green:0.12 blue:0.15 alpha:1.0] setFill];
    [circle fill];

    NSString *letter = @"C";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:rect.size.width * 0.50 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSSize size = [letter sizeWithAttributes:attrs];
    [letter drawAtPoint:NSMakePoint(NSMidX(rect) - size.width / 2.0,
                                    NSMidY(rect) - size.height / 2.0 - rect.size.height * 0.02)
         withAttributes:attrs];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3 && argc != 4) return 2;
        NSInteger size = [[NSString stringWithUTF8String:argv[1]] integerValue];
        NSString *outPath = [NSString stringWithUTF8String:argv[2]];
        NSString *sourcePath = argc == 4 ? [NSString stringWithUTF8String:argv[3]] : nil;
        NSImage *source = sourcePath.length ? [[NSImage alloc] initWithContentsOfFile:sourcePath] : nil;

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:size
                                                                        pixelsHigh:size
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0
                                                                      bitsPerPixel:0];
        rep.size = NSMakeSize(size, size);
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = context;
        context.imageInterpolation = NSImageInterpolationHigh;

        CGFloat scale = size / 1024.0;
        NSRect canvas = NSMakeRect(0, 0, size, size);
        [[NSColor clearColor] setFill];
        NSRectFill(canvas);

        NSRect tileRect = NSInsetRect(canvas, 56 * scale, 56 * scale);
        NSBezierPath *tile = RoundedRect(tileRect, 210 * scale);
        [[NSColor whiteColor] setFill];
        [tile fill];
        [[NSColor colorWithCalibratedWhite:0.0 alpha:0.08] setStroke];
        tile.lineWidth = 2 * scale;
        [tile stroke];

        NSRect imageRect = NSInsetRect(canvas, 186 * scale, 186 * scale);
        if (source) {
            [source drawInRect:imageRect
                      fromRect:NSZeroRect
                     operation:NSCompositingOperationSourceOver
                      fraction:1.0
                respectFlipped:NO
                         hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        } else {
            DrawFallbackMark(imageRect);
        }

        DrawGradientRing(NSInsetRect(canvas, 118 * scale, 118 * scale), 34 * scale);

        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:outPath atomically:YES] ? 0 : 1;
    }
}
