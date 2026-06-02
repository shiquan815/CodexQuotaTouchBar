#import <Cocoa/Cocoa.h>

@interface RateWindow : NSObject
@property(nonatomic) NSInteger usedPercent;
@property(nonatomic) NSInteger windowMinutes;
@property(nonatomic, strong, nullable) NSDate *resetsAt;
- (NSInteger)remainingPercent;
@end

@implementation RateWindow
- (NSInteger)remainingPercent { return MAX(0, MIN(100, 100 - self.usedPercent)); }
@end

@interface QuotaSnapshot : NSObject
@property(nonatomic, strong, nullable) RateWindow *primary;
@property(nonatomic, strong, nullable) RateWindow *secondary;
@property(nonatomic, copy) NSString *source;
@property(nonatomic, strong) NSDate *updatedAt;
@end

@implementation QuotaSnapshot
@end

static NSString *FindCodex(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *appPath = @"/Applications/Codex.app/Contents/Resources/codex";
    if ([fm isExecutableFileAtPath:appPath]) return appPath;

    NSString *extensions = [@"~/.vscode/extensions" stringByExpandingTildeInPath];
    NSArray<NSString *> *children = [fm contentsOfDirectoryAtPath:extensions error:nil];
    NSMutableArray<NSString *> *matches = NSMutableArray.array;
    for (NSString *child in children) {
        if ([child hasPrefix:@"openai.chatgpt-"] && [child containsString:@"darwin"]) {
            [matches addObject:child];
        }
    }
    [matches sortUsingSelector:@selector(compare:)];
    for (NSString *child in matches.reverseObjectEnumerator) {
        NSString *path = [extensions stringByAppendingPathComponent:[child stringByAppendingPathComponent:@"bin/macos-x86_64/codex"]];
        if ([fm isExecutableFileAtPath:path]) return path;
    }

    NSTask *task = NSTask.new;
    task.launchPath = @"/usr/bin/which";
    task.arguments = @[@"codex"];
    NSPipe *pipe = NSPipe.pipe;
    task.standardOutput = pipe;
    task.standardError = NSPipe.pipe;
    @try {
        [task launch];
        [task waitUntilExit];
        if (task.terminationStatus != 0) return nil;
        NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
        NSString *path = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        path = [path stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return path.length ? path : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static RateWindow *WindowFromDictionary(NSDictionary *dict, BOOL snakeCase) {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    id used = dict[snakeCase ? @"used_percent" : @"usedPercent"];
    if (![used respondsToSelector:@selector(integerValue)]) return nil;
    RateWindow *window = RateWindow.new;
    window.usedPercent = [used integerValue];
    id minutes = dict[snakeCase ? @"window_minutes" : @"windowDurationMins"];
    window.windowMinutes = [minutes respondsToSelector:@selector(integerValue)] ? [minutes integerValue] : 0;
    id reset = dict[snakeCase ? @"resets_at" : @"resetsAt"];
    if ([reset respondsToSelector:@selector(doubleValue)]) {
        window.resetsAt = [NSDate dateWithTimeIntervalSince1970:[reset doubleValue]];
    }
    return window;
}

static QuotaSnapshot *SnapshotFromRateLimits(NSDictionary *limits, NSString *source, BOOL snakeCase) {
    if (![limits isKindOfClass:NSDictionary.class]) return nil;
    QuotaSnapshot *snapshot = QuotaSnapshot.new;
    snapshot.primary = WindowFromDictionary(limits[@"primary"], snakeCase);
    snapshot.secondary = WindowFromDictionary(limits[@"secondary"], snakeCase);
    snapshot.source = source;
    snapshot.updatedAt = NSDate.date;
    return snapshot.primary || snapshot.secondary ? snapshot : nil;
}

static QuotaSnapshot *ParseJSONLines(NSData *data) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *line in lines.reverseObjectEnumerator) {
        if (![line containsString:@"\"id\":2"]) continue;
        NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
        if (![json isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *result = json[@"result"];
        NSDictionary *limits = result[@"rateLimits"];
        QuotaSnapshot *snapshot = SnapshotFromRateLimits(limits, @"app-server", NO);
        if (snapshot) return snapshot;
    }
    return nil;
}

static QuotaSnapshot *ReadJSONLFallback(void) {
    NSString *sessions = [@"~/.codex/sessions" stringByExpandingTildeInPath];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:sessions];
    NSString *latest = nil;
    NSDate *latestDate = NSDate.distantPast;
    for (NSString *path in enumerator) {
        if (![path hasSuffix:@".jsonl"]) continue;
        NSString *full = [sessions stringByAppendingPathComponent:path];
        NSDate *modified = [fm attributesOfItemAtPath:full error:nil][NSFileModificationDate];
        if ([modified compare:latestDate] == NSOrderedDescending) {
            latest = full;
            latestDate = modified;
        }
    }
    if (!latest) return nil;
    NSString *text = [NSString stringWithContentsOfFile:latest encoding:NSUTF8StringEncoding error:nil];
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSString *line in lines.reverseObjectEnumerator) {
        if (![line containsString:@"\"rate_limits\""]) continue;
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSDictionary *payload = json[@"payload"];
        QuotaSnapshot *snapshot = SnapshotFromRateLimits(payload[@"rate_limits"], @"jsonl fallback", YES);
        if (snapshot) return snapshot;
    }
    return nil;
}

@interface CodexClient : NSObject
- (void)fetch:(void (^)(QuotaSnapshot *_Nullable snapshot, NSError *_Nullable error))completion;
@end

@implementation CodexClient
- (void)fetch:(void (^)(QuotaSnapshot *_Nullable snapshot, NSError *_Nullable error))completion {
    NSString *codex = FindCodex();
    if (!codex) {
        completion(ReadJSONLFallback(), [NSError errorWithDomain:@"CodexQuota" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Codex not found"}]);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSTask *task = NSTask.new;
        task.launchPath = codex;
        task.arguments = @[@"app-server", @"--listen", @"stdio://"];
        NSPipe *input = NSPipe.pipe;
        NSPipe *output = NSPipe.pipe;
        NSPipe *err = NSPipe.pipe;
        task.standardInput = input;
        task.standardOutput = output;
        task.standardError = err;

        @try {
            [task launch];
        } @catch (NSException *exception) {
            completion(ReadJSONLFallback(), [NSError errorWithDomain:@"CodexQuota" code:2 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Launch failed"}]);
            return;
        }

        void (^send)(NSDictionary *) = ^(NSDictionary *object) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
            if (!json) return;
            NSMutableData *line = json.mutableCopy;
            [line appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
            [input.fileHandleForWriting writeData:line];
        };

        send(@{@"jsonrpc": @"2.0", @"id": @1, @"method": @"initialize",
               @"params": @{@"clientInfo": @{@"name": @"codex-quota-touchbar", @"version": @"0.1.0", @"title": @"Codex Quota Touch Bar"},
                            @"capabilities": @{@"experimentalApi": @YES,
                                               @"optOutNotificationMethods": @[@"thread/started", @"thread/updated"]}}});
        [NSThread sleepForTimeInterval:0.15];
        send(@{@"jsonrpc": @"2.0", @"method": @"initialized", @"params": NSNull.null});
        [NSThread sleepForTimeInterval:0.15];
        send(@{@"jsonrpc": @"2.0", @"id": @2, @"method": @"account/rateLimits/read", @"params": NSNull.null});
        [NSThread sleepForTimeInterval:2.0];
        [task terminate];
        NSData *data = [output.fileHandleForReading readDataToEndOfFile];
        QuotaSnapshot *snapshot = ParseJSONLines(data) ?: ReadJSONLFallback();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (snapshot) {
                completion(snapshot, nil);
            } else {
                NSData *errData = [err.fileHandleForReading readDataToEndOfFile];
                NSString *message = [[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] ?: @"No quota data";
                completion(nil, [NSError errorWithDomain:@"CodexQuota" code:3 userInfo:@{NSLocalizedDescriptionKey: message}]);
            }
        });
    });
}
@end

@interface TouchBarController : NSObject <NSTouchBarDelegate>
@property(nonatomic, strong) QuotaSnapshot *snapshot;
@property(nonatomic, strong) NSDateFormatter *timeFormatter;
@property(nonatomic, strong) NSDateFormatter *dateFormatter;
@property(nonatomic, weak) NSTextField *primaryRemainingLabel;
@property(nonatomic, weak) NSTextField *primaryResetLabel;
@property(nonatomic, weak) NSView *primaryBarView;
@property(nonatomic, weak) NSTextField *secondaryRemainingLabel;
@property(nonatomic, weak) NSTextField *secondaryResetLabel;
@property(nonatomic, weak) NSView *secondaryBarView;
@property(nonatomic, strong) NSButtonTouchBarItem *trayButtonItem;
- (NSTouchBar *)makeTouchBar;
- (void)refreshVisiblePanel;
- (void)presentSystemModalIfPossible;
- (void)addSystemTrayButton;
- (void)removeSystemTrayButton;
@end

@implementation TouchBarController
- (instancetype)init {
    self = [super init];
    _snapshot = QuotaSnapshot.new;
    _timeFormatter = NSDateFormatter.new;
    _timeFormatter.dateFormat = @"HH:mm";
    _dateFormatter = NSDateFormatter.new;
    _dateFormatter.dateFormat = @"M月d日";
    return self;
}

- (NSTouchBar *)makeTouchBar {
    NSTouchBar *bar = NSTouchBar.new;
    bar.delegate = self;
    bar.customizationIdentifier = @"codex.quota.touchbar";
    bar.defaultItemIdentifiers = @[@"codex.panel"];
    return bar;
}

- (NSButtonTouchBarItem *)systemTrayButton {
    NSButtonTouchBarItem *item = [NSButtonTouchBarItem buttonTouchBarItemWithIdentifier:@"codex.quota.tray"
                                                                                  image:[self codexTrayIcon]
                                                                                 target:NSApp.delegate
                                                                                 action:@selector(showTouchBar)];
    item.customizationLabel = @"Codex Quota";
    return item;
}

- (NSImage *)codexTrayIcon {
    NSString *iconPath = [NSBundle.mainBundle pathForResource:@"AppIcon" ofType:@"icns"];
    NSImage *bundleIcon = iconPath ? [[NSImage alloc] initWithContentsOfFile:iconPath] : nil;
    if (bundleIcon) {
        bundleIcon.size = NSMakeSize(26, 26);
        bundleIcon.template = NO;
        return bundleIcon;
    }

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(26, 26)];
    [image lockFocus];

    NSRect bounds = NSMakeRect(1, 1, 24, 24);
    NSBezierPath *circle = [NSBezierPath bezierPathWithOvalInRect:bounds];
    [[NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.16 alpha:1.0] setFill];
    [circle fill];
    [[NSColor colorWithCalibratedRed:0.46 green:1.0 blue:0.16 alpha:1.0] setStroke];
    circle.lineWidth = 2.0;
    [circle stroke];

    NSString *letter = @"C";
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:15 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: NSColor.whiteColor
    };
    NSSize size = [letter sizeWithAttributes:attrs];
    [letter drawAtPoint:NSMakePoint((26 - size.width) / 2.0, (26 - size.height) / 2.0 - 0.5)
         withAttributes:attrs];

    [image unlockFocus];
    image.template = NO;
    return image;
}

- (nullable NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    if (![identifier isEqualToString:@"codex.panel"]) return nil;

    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    item.view = [self makePanelView];
    return item;
}

- (NSView *)makePanelView {
    NSView *panel = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 520, 30)];

    NSButton *close = [NSButton buttonWithTitle:@"×" target:NSApp.delegate action:@selector(hideTouchBar)];
    close.bezelStyle = NSBezelStyleCircular;
    close.font = [NSFont systemFontOfSize:17 weight:NSFontWeightBold];
    close.frame = NSMakeRect(2, 3, 24, 24);
    [panel addSubview:close];

    NSImageView *brand = [[NSImageView alloc] initWithFrame:NSMakeRect(38, 4, 22, 22)];
    brand.image = [self codexTrayIcon];
    brand.imageScaling = NSImageScaleProportionallyDown;
    [panel addSubview:brand];

    [panel addSubview:[self rowWithTitle:@"5h"
                                  window:self.snapshot.primary
                                       y:16
                                 weekly:NO]];
    [panel addSubview:[self rowWithTitle:@"week"
                                  window:self.snapshot.secondary
                                       y:1
                                 weekly:YES]];

    return panel;
}

- (NSView *)rowWithTitle:(NSString *)title window:(RateWindow *)window y:(CGFloat)y weekly:(BOOL)weekly {
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(92, y, 420, 13)];
    [row addSubview:[self label:title frame:NSMakeRect(0, -1, 58, 15) font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold] color:NSColor.whiteColor alignment:NSTextAlignmentLeft]];
    NSView *bar = [self segmentedBarForWindow:window frame:NSMakeRect(66, 1, 198, 10)];
    [row addSubview:bar];

    NSString *remaining = window ? [NSString stringWithFormat:@"%ld%%", (long)window.remainingPercent] : @"--";
    NSTextField *remainingLabel = [self label:remaining frame:NSMakeRect(285, -1, 44, 15) font:[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold] color:NSColor.whiteColor alignment:NSTextAlignmentLeft];
    [row addSubview:remainingLabel];

    NSTextField *resetLabel = [self label:[self resetTextForWindow:window weekly:weekly] frame:NSMakeRect(348, -1, 72, 15) font:[NSFont systemFontOfSize:13 weight:NSFontWeightMedium] color:[NSColor colorWithWhite:0.88 alpha:1.0] alignment:NSTextAlignmentLeft];
    [row addSubview:resetLabel];

    if (weekly) {
        self.secondaryBarView = bar;
        self.secondaryRemainingLabel = remainingLabel;
        self.secondaryResetLabel = resetLabel;
    } else {
        self.primaryBarView = bar;
        self.primaryRemainingLabel = remainingLabel;
        self.primaryResetLabel = resetLabel;
    }

    return row;
}

- (NSString *)resetTextForWindow:(RateWindow *)window weekly:(BOOL)weekly {
    if (!window.resetsAt) return @"--";
    NSTimeInterval seconds = MAX(0, [window.resetsAt timeIntervalSinceDate:NSDate.date]);
    NSInteger totalMinutes = (NSInteger)ceil(seconds / 60.0);
    if (weekly && seconds > 86400.0) {
        NSInteger days = (NSInteger)ceil(seconds / 86400.0);
        return [NSString stringWithFormat:@"%ld天", (long)days];
    }
    NSInteger hours = totalMinutes / 60;
    NSInteger minutes = totalMinutes % 60;
    return [NSString stringWithFormat:@"%ldh %ldmin", (long)hours, (long)minutes];
}

- (void)refreshVisiblePanel {
    [self updateRemainingLabel:self.primaryRemainingLabel resetLabel:self.primaryResetLabel bar:self.primaryBarView window:self.snapshot.primary weekly:NO];
    [self updateRemainingLabel:self.secondaryRemainingLabel resetLabel:self.secondaryResetLabel bar:self.secondaryBarView window:self.snapshot.secondary weekly:YES];
}

- (void)updateRemainingLabel:(NSTextField *)remainingLabel resetLabel:(NSTextField *)resetLabel bar:(NSView *)bar window:(RateWindow *)window weekly:(BOOL)weekly {
    if (remainingLabel) {
        remainingLabel.stringValue = window ? [NSString stringWithFormat:@"%ld%%", (long)window.remainingPercent] : @"--";
    }
    if (resetLabel) {
        resetLabel.stringValue = [self resetTextForWindow:window weekly:weekly];
    }
    if (bar) {
        NSRect frame = bar.frame;
        NSView *row = bar.superview;
        [bar removeFromSuperview];
        NSView *newBar = [self segmentedBarForWindow:window frame:frame];
        [row addSubview:newBar positioned:NSWindowBelow relativeTo:remainingLabel];
        if (weekly) {
            self.secondaryBarView = newBar;
        } else {
            self.primaryBarView = newBar;
        }
    }
}

- (NSView *)segmentedBarForWindow:(RateWindow *)window frame:(NSRect)frame {
    NSView *bar = [[NSView alloc] initWithFrame:frame];
    NSInteger active = window ? (NSInteger)ceil(window.remainingPercent / 5.0) : 0;
    active = MAX(0, MIN(20, active));
    NSColor *activeColor = [self barColorForRemainingPercent:(window ? window.remainingPercent : 0)];
    CGFloat segmentWidth = 7.8;
    CGFloat gap = 2.0;
    for (NSInteger index = 0; index < 20; index++) {
        NSView *segment = [[NSView alloc] initWithFrame:NSMakeRect(index * (segmentWidth + gap), 0, segmentWidth, 8.5)];
        segment.wantsLayer = YES;
        segment.layer.cornerRadius = 3.0;
        segment.layer.backgroundColor = (index < active ? activeColor.CGColor : [NSColor colorWithWhite:0.28 alpha:1.0].CGColor);
        segment.layer.borderWidth = 0.5;
        segment.layer.borderColor = [NSColor colorWithWhite:0.75 alpha:0.35].CGColor;
        [bar addSubview:segment];
    }
    return bar;
}

- (NSColor *)barColorForRemainingPercent:(NSInteger)remainingPercent {
    CGFloat t = MIN(1.0, MAX(0.0, (CGFloat)remainingPercent / 100.0));
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    if (t < 0.5) {
        red = 1.0;
        green = 0.22 + t * 1.56;
    } else {
        red = 1.0 - (t - 0.5) * 1.65;
        green = 1.0;
    }
    return [NSColor colorWithCalibratedRed:red green:green blue:0.12 alpha:1.0];
}

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame font:(NSFont *)font color:(NSColor *)color alignment:(NSTextAlignment)alignment {
    NSTextField *label = [NSTextField labelWithString:text];
    label.frame = frame;
    label.font = font;
    label.textColor = color;
    label.alignment = alignment;
    label.lineBreakMode = NSLineBreakByClipping;
    return label;
}

- (void)presentSystemModalIfPossible {
    SEL selector = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    if (![NSTouchBar respondsToSelector:selector]) return;
    NSTouchBar *bar = [self makeTouchBar];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [NSTouchBar performSelector:selector withObject:bar withObject:@"codex.quota.tray"];
#pragma clang diagnostic pop
}

- (void)addSystemTrayButton {
    SEL addSelector = NSSelectorFromString(@"addSystemTrayItem:");
    if (![NSTouchBarItem respondsToSelector:addSelector]) return;
    if (!self.trayButtonItem) {
        self.trayButtonItem = [self systemTrayButton];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [NSTouchBarItem performSelector:addSelector withObject:self.trayButtonItem];
#pragma clang diagnostic pop
}

- (void)removeSystemTrayButton {
    SEL removeSelector = NSSelectorFromString(@"removeSystemTrayItem:");
    if (![NSTouchBarItem respondsToSelector:removeSelector]) return;
    NSButtonTouchBarItem *item = self.trayButtonItem ?: [NSButtonTouchBarItem buttonTouchBarItemWithIdentifier:@"codex.quota.tray"
                                                                                                         title:@"Codex"
                                                                                                        target:nil
                                                                                                        action:nil];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [NSTouchBarItem performSelector:removeSelector withObject:item];
#pragma clang diagnostic pop
    self.trayButtonItem = nil;
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) CodexClient *client;
@property(nonatomic, strong) TouchBarController *touchBarController;
@property(nonatomic, strong) QuotaSnapshot *latest;
@property(nonatomic) dispatch_source_t dataRefreshTimer;
@property(nonatomic) dispatch_source_t trayKeepAliveTimer;
@property(nonatomic) dispatch_source_t displayRefreshTimer;
@property(nonatomic) BOOL isFetching;
@property(nonatomic) BOOL touchBarPanelVisible;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.client = CodexClient.new;
    self.touchBarController = TouchBarController.new;
    self.latest = QuotaSnapshot.new;
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [self menuBarIcon];
    self.statusItem.button.imagePosition = NSImageLeft;
    self.statusItem.button.title = @" --";

    NSMenu *menu = NSMenu.new;
    [menu addItemWithTitle:@"Refresh" action:@selector(refreshNow) keyEquivalent:@"r"];
    [menu addItemWithTitle:@"Show Touch Bar" action:@selector(showTouchBar) keyEquivalent:@"t"];
    [menu addItem:NSMenuItem.separatorItem];
    [menu addItemWithTitle:@"Quit" action:@selector(quit) keyEquivalent:@"q"];
    self.statusItem.menu = menu;

    NSApp.touchBar = [self.touchBarController makeTouchBar];
    [self.touchBarController addSystemTrayButton];
    [self refreshNow];
    [self startTimers];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self
                                                       selector:@selector(activeApplicationChanged:)
                                                           name:NSWorkspaceDidActivateApplicationNotification
                                                         object:nil];
}

- (void)startTimers {
    self.dataRefreshTimer = [self repeatingMainTimerWithInterval:30.0 block:^{
        [self refreshNow];
    }];
    self.trayKeepAliveTimer = [self repeatingMainTimerWithInterval:15.0 block:^{
        [self keepTrayButtonAlive];
    }];
    self.displayRefreshTimer = [self repeatingMainTimerWithInterval:10.0 block:^{
        [self refreshDisplayedCountdowns];
    }];
}

- (dispatch_source_t)repeatingMainTimerWithInterval:(NSTimeInterval)interval block:(dispatch_block_t)block {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    uint64_t nanoseconds = (uint64_t)(interval * (NSTimeInterval)NSEC_PER_SEC);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, nanoseconds), nanoseconds, (uint64_t)(1.0 * (NSTimeInterval)NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, block);
    dispatch_resume(timer);
    return timer;
}

- (NSImage *)menuBarIcon {
    NSString *iconPath = [NSBundle.mainBundle pathForResource:@"AppIcon" ofType:@"icns"];
    NSImage *image = iconPath ? [[NSImage alloc] initWithContentsOfFile:iconPath] : nil;
    if (!image) return nil;
    image.size = NSMakeSize(18, 18);
    image.template = NO;
    return image;
}

- (NSString *)titleForSnapshot:(QuotaSnapshot *)snapshot refreshing:(BOOL)refreshing {
    NSString *five = snapshot.primary ? [NSString stringWithFormat:@"%ld%%", (long)snapshot.primary.remainingPercent] : @"--";
    NSString *week = snapshot.secondary ? [NSString stringWithFormat:@"%ld%%", (long)snapshot.secondary.remainingPercent] : @"--";
    return [NSString stringWithFormat:@" 5h %@ W %@%@", five, week, refreshing ? @"..." : @""];
}

- (void)refreshNow {
    if (self.isFetching) return;
    self.isFetching = YES;
    self.statusItem.button.title = [self titleForSnapshot:self.latest refreshing:YES];
    [self.client fetch:^(QuotaSnapshot *snapshot, NSError *error) {
        self.isFetching = NO;
        if (snapshot) self.latest = snapshot;
        self.statusItem.button.title = [self titleForSnapshot:self.latest refreshing:NO];
        self.touchBarController.snapshot = self.latest;
        [self.touchBarController refreshVisiblePanel];
        [self.touchBarController addSystemTrayButton];
    }];
}

- (void)showTouchBar {
    [NSApp activateIgnoringOtherApps:YES];
    [self refreshNow];
    [self showTouchBarPanel];
}

- (void)showTouchBarPanel {
    self.touchBarPanelVisible = YES;
    self.touchBarController.snapshot = self.latest;
    NSApp.touchBar = [self.touchBarController makeTouchBar];
    [self.touchBarController presentSystemModalIfPossible];
}

- (void)keepTrayButtonAlive {
    self.touchBarController.snapshot = self.latest;
    [self.touchBarController addSystemTrayButton];
}

- (void)refreshDisplayedCountdowns {
    self.statusItem.button.title = [self titleForSnapshot:self.latest refreshing:self.isFetching];
    self.touchBarController.snapshot = self.latest;
    [self.touchBarController refreshVisiblePanel];
    [self.touchBarController addSystemTrayButton];
}

- (void)activeApplicationChanged:(NSNotification *)notification {
    [self keepTrayButtonAlive];
}

- (void)hideTouchBar {
    self.touchBarPanelVisible = NO;
    SEL selector = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    if (![NSTouchBar respondsToSelector:selector]) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [NSTouchBar performSelector:selector withObject:@"codex.quota.tray"];
#pragma clang diagnostic pop
}

- (void)quit {
    if (self.dataRefreshTimer) dispatch_source_cancel(self.dataRefreshTimer);
    if (self.trayKeepAliveTimer) dispatch_source_cancel(self.trayKeepAliveTimer);
    if (self.displayRefreshTimer) dispatch_source_cancel(self.displayRefreshTimer);
    [self.touchBarController removeSystemTrayButton];
    [NSApp terminate:nil];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;
        AppDelegate *delegate = AppDelegate.new;
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
