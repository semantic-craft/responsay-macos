#import "PaddleORTTensor.h"

@implementation PaddleORTTensor

- (instancetype)initWithFloatData:(NSData *)floatData shape:(NSArray<NSNumber *> *)shape {
    self = [super init];
    if (self) {
        _floatData = [floatData copy];
        _shape = [shape copy];
    }
    return self;
}

@end
