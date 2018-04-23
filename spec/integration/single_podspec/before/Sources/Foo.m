@interface Foo: NSObject
@end

@implementation Foo
+ (void)load { NSLog(@"Loaded %@", self); }
@end