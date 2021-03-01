//
//  NSObject+KVOController.h
//  LSKVOController
//
//  Created by Marshal on 2021/2/23.
//  使用方便的观察者

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void(^CallBack)(__nullable id observer, id value, id oldValue);

typedef void(^SubCallBack)(__nullable id observer, id value, id _Nullable subKeyPath, id _Nullable subValue);

@interface NSObject (LSKVOController)

/*
 注意: 只有属性才支持监听，即有setter和getter方法，想获取旧值必须有getter方法
 不支持的监听类型,包括自定义struct结构体，union联合体, c类型数组[]
 id对象返回的还是对象
 NSNumber、Class、SEL、Pointer(指针类型)、char *返回的均为NSValue类型
 同一个键值、同一个观察者只能有一个回调，后添加的覆盖先前的
 */


/// 添加block监听
/// @param observer 观察者
/// @param keyPath 被观察的属性，会因为没有setter和getter方法而报错
/// @param callback 回调block(id observer, id newValue, id oldValue) 观察者、新值、旧值
/// @param initialResponse 是否默认回调一次
- (void)ls_addObserver:(id)observer keyPath:(NSString * _Nonnull)keyPath callBack:(CallBack)callback initialResponse:(BOOL)initialResponse;
//默认不回调
- (void)ls_addObserver:(id)observer keyPath:(NSString * _Nonnull)keyPath callBack:(CallBack)callback;


/// 给多个属性添加block监听
/// @param observer 观察者
/// @param keyPaths 被观察的属性集合，会因为没有setter和getter方法而报错
/// @param callback 回调block(id observer, id newValue, id oldValue) 观察者、新值、旧值
/// @param initialResponse 是否默认回调一次
- (void)ls_addObserver:(id)observer keyPaths:(NSArray<NSString *> * _Nonnull)keyPaths callBack:(CallBack)callback initialResponse:(BOOL)initialResponse;
//默认不回调
- (void)ls_addObserver:(id)observer keyPaths:(NSArray<NSString *> * _Nonnull)keyPaths callBack:(CallBack)callback;



/// 给指定键值属性添加子属性监听block，当属性的某个子属性更改时，则回调当前属性(指定键值属性的子属性不支持监听时，改变不会回调)
/// @param observer 观察者
/// @param keyPath 被观察的属性集合，会因为没有setter和getter方法而报错(子属性也必须有setter和getter方法)
/// @param callback 回调block(id observer, id newValue, id oldValue) 观察者、新值、旧值
/// @param initialResponse 是否默认回调一次
- (void)ls_addSubObserver:(id)observer keyPath:(NSString * _Nonnull)keyPath callBack:(SubCallBack)callback initialResponse:(BOOL)initialResponse;
//默认不回调
- (void)ls_addSubObserver:(id)observer keyPath:(NSString * _Nonnull)keyPath callBack:(SubCallBack)callback;



/// 给属性添加子属性监听block，指定键值的子属性更改时，则回调当前属性
/// @param observer 观察者
/// @param keyPath 观察的属性键值
/// @param subkeyPaths 被观察的属性的响应子属性白名单集合，会因为没有setter和getter方法而报错(子属性也必须有setter和getter方法)
/// @param callback 回调block(id observer, id newValue, id oldValue) 观察者、新值、旧值
/// @param initialResponse 是否默认回调一次
- (void)ls_addSubObserver:(id)observer keyPath:(NSString * _Nonnull)keyPath subKeyPaths:(NSArray<NSString *> *)subkeyPaths callBack:(SubCallBack)callback initialResponse:(BOOL)initialResponse;
//默认不回调
- (void)ls_addSubObserver:(id)observer keyPath:(NSString * _Nonnull)keyPath subKeyPaths:(NSArray<NSString *> *)subkeyPaths callBack:(SubCallBack)callback;



/// 添加SEL监听
/// @param observer 观察者
/// @param keyPath 被观察的键值，会因为没有setter和getter方法而报错
/// @param sel 回调SEL 两个参数 observer、newValue 新值、旧值
/// @param initialResponse 是否默认回调一次
- (void)ls_addObserver:(id)observer keyPath:(NSString * _Nonnull)keyPath selector:(nonnull SEL)sel initialResponse:(BOOL)initialResponse;
//默认不回调
- (void)ls_addObserver:(id)observer keyPath:(NSString * _Nonnull)keyPath selector:(nonnull SEL)sel;


/// 添加SEL监听
/// @param observer 观察者
/// @param keyPaths 被观察的键值集合，会因为没有setter和getter方法而报错
/// @param sel 回调SEL 两个参数 observer、newValue 新值、旧值
/// @param initialResponse 是否默认回调一次
- (void)ls_addObserver:(id)observer keyPaths:(NSArray<NSString *> * _Nonnull)keyPaths selector:(nonnull SEL)sel initialResponse:(BOOL)initialResponse;
//默认不回调
- (void)ls_addObserver:(id)observer keyPaths:(NSArray<NSString *> * _Nonnull)keyPaths selector:(nonnull SEL)sel;

@end

NS_ASSUME_NONNULL_END
