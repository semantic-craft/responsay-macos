#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PaddleORTTensor : NSObject

@property(nonatomic, readonly) NSData *floatData;
@property(nonatomic, readonly) NSArray<NSNumber *> *shape;

- (instancetype)initWithFloatData:(NSData *)floatData shape:(NSArray<NSNumber *> *)shape;

@end

NS_ASSUME_NONNULL_END
