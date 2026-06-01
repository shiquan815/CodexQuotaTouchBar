#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static BOOL ContainsAny(NSString *value) {
    NSArray<NSString *> *needles = @[@"TouchBar", @"Touch Bar", @"SystemTray", @"ControlStrip", @"Control Strip", @"systemTray", @"controlStrip"];
    for (NSString *needle in needles) {
        if ([value rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static void PrintMethods(Class cls, NSString *className) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    for (unsigned int index = 0; index < count; index++) {
        SEL sel = method_getName(methods[index]);
        NSString *name = NSStringFromSelector(sel);
        if (ContainsAny(name)) {
            printf("METHOD %s %s\n", className.UTF8String, name.UTF8String);
        }
    }
    free(methods);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        int count = objc_getClassList(NULL, 0);
        Class *classes = (Class *)calloc((size_t)count, sizeof(Class));
        objc_getClassList(classes, count);

        for (int index = 0; index < count; index++) {
            Class cls = classes[index];
            NSString *name = NSStringFromClass(cls);
            if (ContainsAny(name)) {
                printf("CLASS %s\n", name.UTF8String);
                PrintMethods(cls, name);
                Class meta = object_getClass(cls);
                PrintMethods(meta, [NSString stringWithFormat:@"+%@", name]);
            }
        }

        NSArray<Class> *interesting = @[
            NSApplication.class,
            NSClassFromString(@"NSTouchBar"),
            NSClassFromString(@"NSCustomTouchBarItem"),
            NSClassFromString(@"NSSharingServicePickerTouchBarItem")
        ];
        for (Class cls in interesting) {
            if (!cls) continue;
            NSString *name = NSStringFromClass(cls);
            PrintMethods(cls, name);
            PrintMethods(object_getClass(cls), [@"+" stringByAppendingString:name]);
        }

        free(classes);
    }
    return 0;
}
