@interface Foo: NSObject
@end

@implementation Forkable
+ (void)load { NSLog(@"<Local> Loaded %@", self); }
@end