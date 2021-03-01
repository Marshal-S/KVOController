//
//  ViewController.m
//  LSKVOController
//
//  Created by Marshal on 2021/2/23.
//

#import "ViewController.h"
#import "NSObject+LSKVOController.h"
#import "LSStudent.h"
#import <objc/message.h>

@interface ViewController ()

@property(nonatomic, strong) LSStudent *student;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    printf("\n\n\n");
    
    _student = [LSStudent alloc];
    _student.dog = [LSDog alloc];
    _student.name = @"小红";
    
    [_student ls_addObserver:self keyPath:@"name" callBack:^(ViewController  *observer, id  _Nonnull value, id  _Nonnull oldValue) {
        NSLog(@"student的name回调:%@", value);
    }];
    //默认响应一次回调
    [_student ls_addObserver:self keyPath:@"name" callBack:^(ViewController  *observer, id  _Nonnull value, id  _Nonnull oldValue) {
        NSLog(@"student的name回调:%@", value);
    } initialResponse:YES];
    
    
    [_student ls_addObserver:self keyPath:@"pointer" callBack:^(ViewController  *observer, id _Nonnull value, id _Nonnull oldValue) {
        int *age = nil;
        [value getValue:&age size:sizeof(int *)];
        NSLog(@"student的pointer回调:%d", *age);
    }];
    
    [_student ls_addObserver:self keyPath:@"cls" callBack:^(ViewController  *observer, id _Nonnull value, id _Nonnull oldValue) {
        Class cls = nil;
        [value getValue:&cls size:sizeof(Class)];
        NSLog(@"student的cls回调:%@", cls);
    }];
    
    [_student ls_addObserver:self keyPath:@"sel" callBack:^(ViewController  *observer, id _Nonnull value, id _Nonnull oldValue) {
        SEL sel = nil;
        [value getValue:&sel size:sizeof(SEL)];
        NSLog(@"student的sel回调:%@", NSStringFromSelector(sel));
    }];

    [_student ls_addObserver:self keyPath:@"block" callBack:^(ViewController  *observer, id _Nonnull value, id _Nonnull oldValue) {
        void(^block)(int a) = value;
        block(10);
        NSLog(@"student的block回调:%@",value);
    }];
    
    [_student ls_addObserver:self keyPath:@"rect" callBack:^(ViewController  *observer, id _Nonnull value, id _Nonnull oldValue) {
        NSLog(@"student的rect回调:%@",value);
    }];
    
    [_student ls_addSubObserver:self keyPath:@"dog" subKeyPaths:@[@"name", @"age"] callBack:^(id  _Nullable observer, LSDog *  _Nonnull value, id  _Nonnull subKeyPath, id  _Nonnull subValue) {
        NSLog(@"student的dog回调:%@--subKeyPath:%@--subValue:%@", value, subKeyPath, subValue);
        NSLog(@"name:%@--age:%ld--color:%@", value.name, value.age, value.color);
    }];
    
    [_student ls_addSubObserver:self keyPath:@"dog" callBack:^(id  _Nullable observer, LSDog *  _Nonnull value, id  _Nonnull subKeyPath, id  _Nonnull subValue) {
        NSLog(@"student的dog回调:%@--subKeyPath:%@--subValue:%@", value, subKeyPath, subValue);
        NSLog(@"name:%@--age:%ld--color:%@", value.name, value.age, value.color);
    }];
}

- (IBAction)onSend:(id)sender {
    self.student.name = @"小明";
    self.student.age = 29;

    int *a = (int *)malloc(sizeof(int));
    *a = 10;
    self.student.pointer = a;

    self.student.cls = NSClassFromString(@"ViewController");
    self.student.sel = @selector(onDelete:);
    
    self.student.rect = CGRectMake(0, 0, 0, 0);
    self.student.point = CGPointMake(1, 1);
    self.student.size = CGSizeMake(2, 2);
    self.student.vector = CGVectorMake(3, 3);
    self.student.insets = UIEdgeInsetsMake(4, 4, 4, 4);
    self.student.offset = UIOffsetMake(5, 5);
    self.student.range = NSMakeRange(6, 6);
    self.student.dirInset = NSDirectionalEdgeInsetsMake(7, 7, 7, 7);
    
    [self.student setBlock:^(int a) {
        NSLog(@"测试一下了: %d", a);
    }];
    
    self.student.dog.color = @"红色";
    self.student.dog.name = @"毛毛";
    self.student.dog.age = 2;
}
- (IBAction)onDelete:(id)sender {
    
}

@end
