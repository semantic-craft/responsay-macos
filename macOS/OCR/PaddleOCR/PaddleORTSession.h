#import <Foundation/Foundation.h>

@class PaddleORTTensor;

NS_ASSUME_NONNULL_BEGIN

@interface PaddleORTSession : NSObject

- (nullable instancetype)initWithModelPath:(NSString *)modelPath
                                threadCount:(NSInteger)threadCount
                                      error:(NSError **)error;

- (nullable PaddleORTTensor *)runWithFloatData:(NSData *)floatData
                                         shape:(NSArray<NSNumber *> *)shape
                                         error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
