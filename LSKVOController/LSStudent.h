//
//  LSStudent.h
//  LSKVOController
//
//  Created by Marshal on 2021/2/24.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "LSDog.h"

NS_ASSUME_NONNULL_BEGIN

@interface LSStudent : NSObject

@property NSString *name;
@property int age;
@property double age4;
@property int *pointer;
@property Class cls;
@property SEL sel;
@property void(^block)(int a);
@property CGRect rect;
@property CGPoint point;
@property CGSize size;
@property CGVector vector;
@property CGAffineTransform trans;
@property UIEdgeInsets insets;
@property UIOffset offset;
@property NSRange range;
@property NSDirectionalEdgeInsets dirInset;

@property LSDog *dog;

@end

NS_ASSUME_NONNULL_END
