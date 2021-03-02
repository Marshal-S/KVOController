//
//  NSObject+KVOController.m
//  LSKVOController
//
//  Created by Marshal on 2021/2/23.
//

#import "NSObject+LSKVOController.h"
#import <objc/message.h>
#import <UIKit/UIGeometry.h>

static const char kKVOAssociatedClassKey = '\0';
static const char kKVOAssociatedMapTableKey = '\0';

typedef enum : NSUInteger {
    LSEncodingTypeBool = 0, // bool
    LSEncodingTypeInt8, //char
    LSEncodingTypeUInt8, // unsinged char
    LSEncodingTypeInt16, //short
    LSEncodingTypeUInt16, // unsinged short
    LSEncodingTypeInt32, //int
    LSEncodingTypeUInt32, //unsinged int
    LSEncodingTypeLong, //long
    LSEncodingTypeULong, //unsigned long
    LSEncodingTypeInt64, // long long
    LSEncodingTypeUInt64, //unsinged long long
    LSEncodingTypeFloat, //float
    LSEncodingTypeDouble, //double
    LSEncodingTypeObject, //对象 id
    LSEncodingTypeClass,  //Class
    LSEncodingTypeSEL,  // SEL
    LSEncodingTypeCString, // char *
    LSEncodingTypePointer, //指针
    
    //结构体
    LSEncodingTypeStructCGRect, //CGRect结构体
    LSEncodingTypeStructCGPoint, //CGPoint结构体
    LSEncodingTypeStructCGSize, //CGSize结构体
    LSEncodingTypeStructCGVector, //CGVector结构体
    LSEncodingTypeStructCGAffineTransform, //CGAffineTransform结构体
    LSEncodingTypeStructUIEdgeInsets, //UIEdgeInsets结构体
    LSEncodingTypeStructUIOffset, //UIOffset结构体
    LSEncodingTypeStructNSRange, //NSRange结构体
    LSEncodingTypeStructNSDirectionalEdgeInsets, //NSDirectionalEdgeInsets结构体
    LSEncodingTypeStructCustom, //自定义struct
    
    LSEncodingTypeBlock, //block
    
    //从这里开始setter和getter方法都不支持了,监听都不支持了
    LSEncodingTypeVoid, //void
    LSEncodingTypeCArray, //c数组
    LSEncodingTypeUnion, //联合体
    LSEncodingTypeUnknown //不知名的
} LSEncodingType;

//回调基础类
@interface _LSKVOInfo : NSObject
{
@public
    __weak id _observer; //观察者
    NSString *_keyPath;
    CallBack _block;
    SEL _sel;
}

@end

@implementation _LSKVOInfo

- (NSUInteger)hash {
    return [_keyPath hash];
}

- (BOOL)isEqual:(id)object
{
  if (nil == object) {
    return NO;
  }
  if (self == object) {
    return YES;
  }
  if (![object isKindOfClass:[self class]]) {
    return NO;
  }
  return [_keyPath isEqualToString:((_LSKVOInfo *)object)->_keyPath];
}

@end

@interface __LSClassKeyPathInfo : NSObject
{
@public
    NSString *_setter;
    NSString *_getter;
    LSEncodingType _type; //setter的EncodingType类型
}

@end

@implementation __LSClassKeyPathInfo
@end

//基础类信息，管理自己的类和对象
@interface _LSClassInfo : NSObject
{
@public
    Class _cls; //创建的新类
    Class _superCls; //原始类
    NSMutableDictionary<NSString *, __LSClassKeyPathInfo *> *_keyPathMap;//每次添加一对setter和getter键值，均指向__LSClassKeyPathInfo对象
    NSHashTable<id> *_hashTable; //该类作为被观察者对象的的弱引用集合，用于判断是否已经设置class了
    dispatch_semaphore_t _semaphore;
}

@end

@implementation _LSClassInfo

- (instancetype)init
{
    self = [super init];
    if (self) {
        _keyPathMap = [NSMutableDictionary dictionary];
        _hashTable = [NSHashTable hashTableWithOptions:(NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality)];
        _semaphore = dispatch_semaphore_create(1);
    }
    return self;
}

#pragma mark --添加子类LSKVONotifying_的class
- (void)_observerClass:(Class)cls info:(_LSKVOInfo *)info {
    //注册新的子类
    Class newCls = objc_allocateClassPair(cls, [NSString stringWithFormat:@"LSKVONotifying_%@", NSStringFromClass(cls)].UTF8String, 0);
    objc_registerClassPair(newCls);
    
    //子类重写dealloc方法实现
    SEL deallocSel = NSSelectorFromString(@"dealloc");
    Method deallocMethod = class_getInstanceMethod(cls, deallocSel);
    class_addMethod(newCls, deallocSel, (IMP)ls_dealloc, method_getTypeEncoding(deallocMethod));
    
    //子类重写class方法实现
    SEL classSel = NSSelectorFromString(@"class");
    Method classMethod = class_getInstanceMethod(cls, classSel);
    class_addMethod(newCls, classSel, (IMP)ls_class, method_getTypeEncoding(classMethod));
    
    _superCls = cls;
    _cls = newCls;
}

#pragma mark --第一次创建被观察者class的时候走这里
- (void)setInfo:(_LSKVOInfo *)info observer:(id)observed  {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    
    //设置对象的类为新的类
    object_setClass(observed, _cls);
    [_hashTable addObject:observed]; //加入集合中
    
    //子类重写setter方法实现,并保存keyPath和setter
    [self addSetterAndSave:info];
    
    //设置KVOInfo信息对应键值
    NSMutableDictionary *infos = [NSMutableDictionary dictionary];
    [infos setObject:info forKey:info->_keyPath];
    
    //设置mapTable其与观察者observer相关
    NSMapTable *mapTable = [[NSMapTable alloc] initWithKeyOptions:(NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality) valueOptions:(NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPersonality) capacity:0];
    [mapTable setObject:infos forKey:info->_observer];
    
    //给对象添加该类的关联
    objc_setAssociatedObject(observed, &kKVOAssociatedClassKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(observed, &kKVOAssociatedMapTableKey, mapTable, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    dispatch_semaphore_signal(_semaphore);
}

#pragma mark --更新创建被观察者对象信息class的时候走这里
- (void)updateInfo:(_LSKVOInfo *)info observer:(id)observed {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    
    //设置对象的类为新的类
    if (![_hashTable containsObject:observed]) {
        object_setClass(observed, _cls);
        [_hashTable addObject:observed]; //加入集合中
    }
    
    //如果没有实现该键值的setter方法，则实现
    __LSClassKeyPathInfo *keyPathInfo = [_keyPathMap objectForKey:info->_keyPath];
    if (!keyPathInfo) {
        //子类重写setter方法实现
        [self addSetterAndSave:info];
    }
    //设置classInfo基本信息
    
    //获取对象对应的mapTable，对象对应的mapTable不一定存在
    //mapTable<id observer, infos<NSDictionary *info>> //以每一个观察者为键值key，以keyPath对应的回调集合为value
    NSMapTable *mapTable = objc_getAssociatedObject(observed, &kKVOAssociatedMapTableKey); //获取当前对象对应的
    if (!mapTable) {
        //初始化mapTable
        mapTable = [[NSMapTable alloc] initWithKeyOptions:(NSPointerFunctionsWeakMemory|NSPointerFunctionsObjectPointerPersonality) valueOptions:(NSPointerFunctionsStrongMemory|NSPointerFunctionsObjectPersonality) capacity:0];
        //设置回调
        NSMutableDictionary *infos = [NSMutableDictionary dictionary];
        [infos setObject:info forKey:info->_keyPath];
        //根据观察者加入mapTable
        [mapTable setObject:infos forKey:info->_observer];
        //加入关联
        objc_setAssociatedObject(observed, &kKVOAssociatedMapTableKey, mapTable, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }else {
        NSMutableDictionary *infos = [mapTable objectForKey:info->_observer];
        if (!infos) {
            infos = [NSMutableDictionary dictionary];
            //根据观察者加入mapTable
            [mapTable setObject:infos forKey:info->_observer];
        }
        [infos setObject:info forKey:info->_keyPath];
    }
    
    //给对象添加该类的关联
    if (!objc_getAssociatedObject(observed, &kKVOAssociatedClassKey)) {
        objc_setAssociatedObject(observed, &kKVOAssociatedClassKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    
    dispatch_semaphore_signal(_semaphore);
}

#pragma mark--响应一次回调方法
- (void)responseWithInfo:(_LSKVOInfo *)info observer:(id)observed {
    if (info->_block) {
        id value = [observed valueForKey:info->_keyPath];
        info->_block(info->_observer, value, value);
    }else if (info->_sel) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        //这个由于不存在循环引用问题，则就不返回observer了
        [info->_observer performSelector:info->_sel withObject:info->_observer withObject:[observed valueForKey:info->_keyPath]];
#pragma clang diagnostic pop
    }
}

#pragma mark --重写class方法，注意这里的self代表着什么
static Class ls_class(id self, SEL _cmd){
    return class_getSuperclass(object_getClass(self));
}

#pragma mark --重写dealloc方法
static void ls_dealloc(id self, SEL _cmd) {
    //class设置回去，后面获取父类也可以[self class],可以避免不必要的麻烦
    object_setClass(self, class_getSuperclass(object_getClass(self)));
}

#pragma mark --重写子类NSNotifying_的setter方法
- (void)addSetterAndSave:(_LSKVOInfo *)info {
    NSString *setter = [NSString stringWithFormat:@"set%@%@:",[[info->_keyPath substringToIndex:1] uppercaseString], [info->_keyPath substringFromIndex:1]];
    __LSClassKeyPathInfo *keyPathInfo = [__LSClassKeyPathInfo alloc];
    keyPathInfo->_setter = setter;
    keyPathInfo->_getter = info->_keyPath;
    
    //没有加入key的情况加入key
    SEL sel = NSSelectorFromString(setter);
    const char *encoding = method_getTypeEncoding(class_getInstanceMethod(_superCls, sel));
    IMP imp = getTypeEncodingImp(encoding, &(keyPathInfo->_type));
    if (!imp) return;
    
    class_addMethod(_cls, sel, imp, encoding);

    //保存对应的键值对，方便获取
    [_keyPathMap setObject:keyPathInfo forKey:info->_keyPath];
    [_keyPathMap setObject:keyPathInfo forKey:setter];
}

#pragma mark --获取setter参数枚举值
IMP getTypeEncodingImp(const char *typeEncoding, LSEncodingType *setterType) {
//    v24@0:8@16   v24@0:8^i16 //从第七位开始才是类型参数
//    printf("%s\n", typeEncoding);
    switch (*(typeEncoding + 7)) {
        case 'B':
            *setterType = LSEncodingTypeBool;
            return (IMP)ls_setterBool;
        case 'c':
            *setterType = LSEncodingTypeInt8;
            return (IMP)ls_setterInt8;
        case 'C':
            *setterType = LSEncodingTypeUInt8;
            return (IMP)ls_setterUInt8;
        case 's':
            *setterType = LSEncodingTypeInt16;
            return (IMP)ls_setterInt16;
        case 'S':
            *setterType = LSEncodingTypeUInt16;
            return (IMP)ls_setterUInt16;
        case 'i':
            *setterType = LSEncodingTypeInt32;
            return (IMP)ls_setterInt32;
        case 'I':
            *setterType = LSEncodingTypeUInt32; //long现在都会变成L类型了，可能某些版本是这个
            return (IMP)ls_setterUInt32;
        case 'l':
            *setterType = LSEncodingTypeLong;
            return (IMP)ls_setterLong;
        case 'L':
            *setterType = LSEncodingTypeULong;
            return (IMP)ls_setterULong;
        case 'q':
            *setterType = LSEncodingTypeInt64;
            return (IMP)ls_setterInt64; // long long
        case 'Q':
            *setterType = LSEncodingTypeUInt64;
            return (IMP)ls_setterUInt64; //unsinged long long
        case 'f':
            *setterType = LSEncodingTypeFloat;
            return (IMP)ls_setterFloat;
        case 'd':
            *setterType = LSEncodingTypeDouble;
            return (IMP)ls_setterDouble;
        case '#':
            *setterType = LSEncodingTypeClass;
            return (IMP)ls_setterClass;
        case ':':
            *setterType = LSEncodingTypeSEL;
            return (IMP)ls_setterSEL;
        case '*':
            *setterType = LSEncodingTypeCString;
            return (IMP)ls_setterCString;
        case '^':
            *setterType = LSEncodingTypePointer;
            return (IMP)ls_setterPointer;
        case '@': {
            if (*(typeEncoding + 8) != '?') {
                *setterType = LSEncodingTypeObject;
                return (IMP)ls_setterObject;
            }
            else {
                *setterType = LSEncodingTypeBlock;
                return (IMP)ls_setterBlock;
            }
        }
        case '{': {
            size_t length = strlen(typeEncoding);
            char *structType = (char *)malloc(sizeof(char) * (length - 7));
            char *p = structType;
            for (size_t i = 8; i < length; i++, p++) {
                char c = *(typeEncoding + i);
                if (c == '=') break;
                *p = c;
            }
            *p = '\0'; //加上尾标
            
            if (strcmp(structType, "CGRect") == 0) {
                *setterType = LSEncodingTypeStructCGRect;
                return (IMP)ls_setterCGRect;
            }else if (strcmp(structType, "CGPoint") == 0) {
                *setterType = LSEncodingTypeStructCGPoint;
                return (IMP)ls_setterCGPoint;
            }else if (strcmp(structType, "CGSize") == 0) {
                *setterType = LSEncodingTypeStructCGSize;
                return (IMP)ls_setterCGSize;
            }else if (strcmp(structType, "CGVector") == 0) {
                *setterType = LSEncodingTypeStructCGVector;
                return (IMP)ls_setterCGVector;
            }else if (strcmp(structType, "CGAffineTransform") == 0) {
                *setterType = LSEncodingTypeStructCGAffineTransform;
                return (IMP)ls_setterCGAffineTransform;
            }else if (strcmp(structType, "UIEdgeInsets") == 0) {
                *setterType = LSEncodingTypeStructUIEdgeInsets;
                return (IMP)ls_setterUIEdgeInsets;
            }else if (strcmp(structType, "UIOffset") == 0) {
                *setterType = LSEncodingTypeStructUIOffset;
                return (IMP)ls_setterUIOffset;
            }else if (strcmp(structType, "_NSRange") == 0) {
                *setterType = LSEncodingTypeStructNSRange;
                return (IMP)ls_setterNSRange;
            }else if (strcmp(structType, "NSDirectionalEdgeInsets") == 0) {
                *setterType = LSEncodingTypeStructNSDirectionalEdgeInsets;
                return (IMP)ls_setterNSDirectionalEdgeInsets;
            }else {
                *setterType = LSEncodingTypeStructCustom;
                break;;
            }
        }
        case 'v':
            *setterType = LSEncodingTypeVoid;
            break;
        case '[':
            *setterType = LSEncodingTypeCArray;
            break;
        case '(':
            *setterType = LSEncodingTypeUnion;
            break;
        default: {
            *setterType = LSEncodingTypeUnknown;
            break;
        }
    }
    return NULL;
}

#pragma mark --重写setter方法实现(IMP)
static void ls_setterBool(id self, SEL _cmd, bool value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, bool))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterInt8(id self, SEL _cmd, int8_t value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, int8_t))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterUInt8(id self, SEL _cmd, uint8_t value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, uint8_t))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterInt16(id self, SEL _cmd, int16_t value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, int16_t))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterUInt16(id self, SEL _cmd, uint16_t value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, uint16_t))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterInt32(id self, SEL _cmd, int32_t value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, int32_t))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterUInt32(id self, SEL _cmd, uint32_t value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, uint32_t))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterLong(id self, SEL _cmd, long value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, long))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterULong(id self, SEL _cmd, unsigned long value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, unsigned long))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterInt64(id self, SEL _cmd, int64_t value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, int64_t))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterUInt64(id self, SEL _cmd, uint64_t value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, uint64_t))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}
static void ls_setterFloat(id self, SEL _cmd, float value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, float))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterDouble(id self, SEL _cmd, double value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, double))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, @(value), oldValue, keyPath);
}

static void ls_setterClass(id self, SEL _cmd, Class value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, Class))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithBytes:&value objCType:@encode(Class)], oldValue, keyPath);
}

static void ls_setterSEL(id self, SEL _cmd, SEL value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, SEL))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithBytes:&value objCType:@encode(SEL)], oldValue, keyPath);
}

static void ls_setterCString(id self, SEL _cmd, char *value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, char *))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithBytes:&value objCType:@encode(char *)], oldValue, keyPath);
}

static void ls_setterPointer(id self, SEL _cmd, void *value) {
    id oldValue = nil, keyPath = nil;
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    ((void (*) (void *, SEL, void *))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithPointer:value], oldValue, keyPath);
}

static void ls_setterObject(id self, SEL _cmd, id value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, id))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, value, oldValue, keyPath);
}

static void ls_setterBlock(id self, SEL _cmd, void(^value)(void)) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, void(^value)(void)))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [self valueForKey:keyPath], oldValue, keyPath);
}

static void ls_setterCGRect(id self, SEL _cmd, CGRect value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, CGRect))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithCGRect:value], oldValue, keyPath);
}

static void ls_setterCGPoint(id self, SEL _cmd, CGPoint value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, CGPoint))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithCGPoint:value], oldValue, keyPath);
}

static void ls_setterCGSize(id self, SEL _cmd, CGSize value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, CGSize))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithCGSize:value], oldValue, keyPath);
}

static void ls_setterCGVector(id self, SEL _cmd, CGVector value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, CGVector))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithCGVector:value], oldValue, keyPath);
}

static void ls_setterCGAffineTransform(id self, SEL _cmd, CGAffineTransform value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, CGAffineTransform))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithCGAffineTransform:value], oldValue, keyPath);
}

static void ls_setterUIEdgeInsets(id self, SEL _cmd, UIEdgeInsets value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, UIEdgeInsets))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithUIEdgeInsets:value], oldValue, keyPath);
}

static void ls_setterUIOffset(id self, SEL _cmd, UIOffset value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, UIOffset))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithUIOffset:value], oldValue, keyPath);
}

static void ls_setterNSRange(id self, SEL _cmd, NSRange value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, NSRange))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithRange:value], oldValue, keyPath);
}

static void ls_setterNSDirectionalEdgeInsets(id self, SEL _cmd, NSDirectionalEdgeInsets value) {
    id oldValue = nil, keyPath = nil;
    //预处理获取keyPath, oldValue, superStruct
    struct objc_super superStruct = ls_setPreHandle(self, _cmd, &oldValue, &keyPath);
    //调用父类的setter方法赋值
    ((void (*) (void *, SEL, NSDirectionalEdgeInsets))(void *)objc_msgSendSuper)(&superStruct, _cmd, value);
    _ls_responseSetter(self, [NSValue valueWithDirectionalEdgeInsets:value], oldValue, keyPath);
}

#pragma mark --预处理获取旧值、keypath、superStruct
struct objc_super ls_setPreHandle(id self, SEL _cmd, id *oldValue, id *keyPath) {
    _LSClassInfo *classInfo = objc_getAssociatedObject(self,  &kKVOAssociatedClassKey);
    //获取keyPathInfo
    __LSClassKeyPathInfo *keyPathInfo = [classInfo->_keyPathMap objectForKey:NSStringFromSelector(_cmd)];
    
    struct objc_super superStruct = {
        .receiver = self,
        .super_class = class_getSuperclass(object_getClass(self)),
    };
    *keyPath = keyPathInfo->_getter;
    *oldValue = getOldValue(&superStruct, keyPathInfo->_type, *keyPath);
    return superStruct;
}

#pragma mark --setter响应回调
void _ls_responseSetter(id self, id value, id oldValue, NSString *keyPath) {
    //响应当前对象添加的对应键值的所有监听
    NSMapTable *mapTable = objc_getAssociatedObject(self, &kKVOAssociatedMapTableKey);
    for (id observer in mapTable) {
        if (observer) {
            NSDictionary *infos = [mapTable objectForKey:observer];
            if (infos) {
                _LSKVOInfo *info = [infos objectForKey:keyPath];
                if (info) {
                    if (info->_block)
                        info->_block(observer, value, oldValue);
                    else if (info->_sel)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        //这个由于不存在循环引用问题，则就不返回observer了
                        [observer performSelector:info->_sel withObject:value withObject:oldValue];
#pragma clang diagnostic pop
                }
            }
        }
    }
}

#pragma mark --调用objc_msgSendSuper获取旧值
id getOldValue(struct objc_super *superStruct, LSEncodingType setterType,  NSString *keyPath) {
    SEL sel = NSSelectorFromString(keyPath);
    switch (setterType) {
        case LSEncodingTypeBool:
            return @(((bool (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeInt8:
            return @(((int8_t (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeUInt8:
            return @(((uint8_t (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeInt16:
            return @(((int16_t (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeUInt16:
            return @(((uint16_t (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeInt32:
            return @(((int32_t (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeUInt32:
            return @(((uint32_t (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeLong:
            return @(((long (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeULong:
            return @(((unsigned long (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeInt64:
            return @(((uint64_t (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeUInt64:
            return @(((uint64_t (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeFloat:
            return @(((double (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
        case LSEncodingTypeDouble:
            return @(((bool (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel));
            
        case LSEncodingTypeObject:
            return ((id (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel);
            
        case LSEncodingTypeClass: {
            Class cls = ((Class (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel);
            return [NSValue valueWithBytes:&cls objCType:@encode(Class)];
        }
        case LSEncodingTypeSEL: {
            SEL cls = ((SEL (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel);
            return [NSValue valueWithBytes:&cls objCType:@encode(SEL)];
        }
        case LSEncodingTypeCString: {
            char *s = ((char * (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel);
            return [NSValue valueWithBytes:&s objCType:@encode(char *)];
        }
        case LSEncodingTypePointer:
            return [NSValue valueWithPointer:((void * (*) (void *, SEL))(void *)objc_msgSendSuper)(superStruct, sel)];
            
        case LSEncodingTypeBlock:
        //结构体不支持旧值，无法直接返回
        case LSEncodingTypeStructCGRect:
        case LSEncodingTypeStructCGPoint:
        case LSEncodingTypeStructCGSize:
        case LSEncodingTypeStructCGVector:
        case LSEncodingTypeStructCGAffineTransform:
        case LSEncodingTypeStructUIEdgeInsets:
        case LSEncodingTypeStructUIOffset:
        case LSEncodingTypeStructNSRange:
        case LSEncodingTypeStructNSDirectionalEdgeInsets:
            return [superStruct->receiver valueForKey:keyPath];
            
        case LSEncodingTypeStructCustom:
        case LSEncodingTypeVoid:
        case LSEncodingTypeCArray:
        case LSEncodingTypeUnion:
        case LSEncodingTypeUnknown:
            return nil; //不支持的类型
    }
}

- (NSUInteger)hash
{
  return [NSStringFromClass(_superCls) hash];
}

- (BOOL)isEqual:(id)object
{
  if (nil == object) {
    return NO;
  }
  if (self == object) {
    return YES;
  }
  if (![object isKindOfClass:[self class]]) {
    return NO;
  }
  return [NSStringFromClass(_superCls) isEqualToString:NSStringFromClass(((_LSClassInfo *)object)->_superCls)];
}

@end

#pragma mark class管理类(_KVOControlelr)
//_KVOControlelr class的管理类，负责管理mapTable的清理工作，类的创建和储存
@interface _KVOControllerClassManager : NSObject
{
@public
    NSMutableDictionary<NSString *, _LSClassInfo *> *_classInfoMap; //类的集合
    dispatch_semaphore_t _semaphore;
}
@end

@implementation _KVOControllerClassManager

- (instancetype)init
{
    self = [super init];
    if (self) {
        _classInfoMap = [NSMutableDictionary dictionary];
        _semaphore = dispatch_semaphore_create(1);
    }
    return self;
}

+ (instancetype)sharedManager {
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

//添加新的观察, initialResponse设置回调时，是否默认回调一次
- (void)observer:(id)observed info:(_LSKVOInfo *)info initialResponse:(BOOL)initialResponse {
    NSString *clsName = NSStringFromClass([observed class]);
    
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    
    _LSClassInfo *classInfo = [_classInfoMap objectForKey:clsName];
    
    if (classInfo) {
        dispatch_semaphore_signal(_semaphore);
        //根据对象更新classInfo的回调信息
        [classInfo updateInfo:info observer:observed];
    }else {
        classInfo = [[_LSClassInfo alloc] init];
        [_classInfoMap setObject:classInfo forKey:clsName];
        //添加新类
        [classInfo _observerClass:object_getClass(observed) info:info];
        
        dispatch_semaphore_signal(_semaphore);
        //根据对象设置classInfo的回调信息
        [classInfo setInfo:info observer:observed];
    }
    if (initialResponse) {
        [classInfo responseWithInfo:info observer:observed];
    }
}

@end


@implementation NSObject (LSKVOController)

#pragma mark --添加监听
//block的基本设置方法
static void ls_addBlockObserver(id observed, id observer, NSString *keyPath, CallBack callback, BOOL initialResponse) {
#ifdef DEBUG
    [NSObject judgeExist:observed keyPath:keyPath];
#endif
    
    _LSKVOInfo *info = [_LSKVOInfo new];
    info->_keyPath = keyPath;
    info->_block = callback;
    info->_observer = observer;
    //设置和获取类信息
    [[_KVOControllerClassManager sharedManager] observer:observed info:info initialResponse:initialResponse];
}

//sel的基本设置方法
static void ls_addSelectorObserver(id observed, id observer, NSString *keyPath, SEL sel, BOOL initialResponse) {
#ifdef DEBUG
    [NSObject judgeExist:observed keyPath:keyPath];
#endif
    
    _LSKVOInfo *info = [_LSKVOInfo new];
    info->_keyPath = keyPath;
    info->_sel = sel;
    info->_observer = observer;
    //设置和获取类信息
    [[_KVOControllerClassManager sharedManager] observer:observed info:info initialResponse:initialResponse];
}


- (void)ls_addObserver:(id)observer keyPath:(NSString *)keyPath callBack:(CallBack)callback {
    ls_addBlockObserver(self, observer, keyPath, callback, NO);
}

- (void)ls_addObserver:(id)observer keyPath:(NSString *)keyPath callBack:(CallBack)callback initialResponse:(BOOL)initialResponse {
    ls_addBlockObserver(self, observer, keyPath, callback, initialResponse);
}


- (void)ls_addObserver:(id)observer keyPaths:(NSArray<NSString *> *)keyPaths callBack:(CallBack)callback {
    for (id keyPath in keyPaths) {
        ls_addBlockObserver(self, observer, keyPath, callback, NO);
    }
}

- (void)ls_addObserver:(id)observer keyPaths:(NSArray<NSString *> *)keyPaths callBack:(CallBack)callback initialResponse:(BOOL)initialResponse {
    for (id keyPath in keyPaths) {
        ls_addBlockObserver(self, observer, keyPath, callback, initialResponse);
    }
}


- (void)ls_addSubObserver:(id)observer keyPath:(NSString *)keyPath callBack:(SubCallBack)callback {
    [self ls_addSubObserver:observer keyPath:keyPath callBack:callback initialResponse:NO];
}

- (void)ls_addSubObserver:(id)observer keyPath:(NSString *)keyPath callBack:(SubCallBack)callback initialResponse:(BOOL)initialResponse {
    __weak id object = ((id (*) (id, SEL))(void *)objc_msgSend)(self, NSSelectorFromString(keyPath));
    
    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList([object class], &propertyCount);
    if (properties) {
        for (unsigned int i = 0; i < propertyCount; i++) {
            NSString *keyPath = [NSString stringWithUTF8String:property_getName(properties[i])];
            ls_addBlockObserver(object, self, keyPath, ^(id  _Nullable observer, id  _Nonnull value, id  _Nonnull oldValue) {
                callback(observer, object, keyPath, value);
            }, NO);
        }
        free(properties);
    }
    //响应一次
    if (initialResponse) {
        callback(observer, object, nil, nil);
    }
}


- (void)ls_addSubObserver:(id)observer keyPath:(NSString *)keyPath subKeyPaths:(NSArray<NSString *> *)subkeyPaths callBack:(SubCallBack)callback {
    [self ls_addSubObserver:observer keyPath:keyPath subKeyPaths:subkeyPaths callBack:callback initialResponse:NO];
}

- (void)ls_addSubObserver:(id)observer keyPath:(NSString *)keyPath subKeyPaths:(NSArray<NSString *> *)subkeyPaths callBack:(SubCallBack)callback initialResponse:(BOOL)initialResponse {
    __weak id object = ((id (*) (id, SEL))(void *)objc_msgSend)(self, NSSelectorFromString(keyPath));
    
    for (id subPath in subkeyPaths) {
        ls_addBlockObserver(object, self, subPath, ^(id  _Nullable observer, id  _Nonnull value, id  _Nonnull oldValue) {
            callback(observer, object, subPath, value);
        }, NO);
    }
    //响应一次
    if (initialResponse) {
        callback(observer, object, nil, nil);
    }
}


- (void)ls_addObserver:(id)observer keyPath:(NSString *)keyPath selector:(SEL)sel {
    ls_addSelectorObserver(self, observer, keyPath, sel, NO);
}

- (void)ls_addObserver:(id)observer keyPath:(NSString *)keyPath selector:(SEL)sel initialResponse:(BOOL)initialResponse {
    ls_addSelectorObserver(self, observer, keyPath, sel, initialResponse);
}


- (void)ls_addObserver:(id)observer keyPaths:(NSArray<NSString *> *)keyPaths selector:(nonnull SEL)sel {
    for (id keyPath in keyPaths) {
        ls_addSelectorObserver(self, observer, keyPath, sel, NO);
    }
}

- (void)ls_addObserver:(id)observer keyPaths:(NSArray<NSString *> *)keyPaths selector:(nonnull SEL)sel initialResponse:(BOOL)initialResponse {
    for (id keyPath in keyPaths) {
        ls_addSelectorObserver(self, observer, keyPath, sel, initialResponse);
    }
}

#pragma mark --debug模式下的keyPath检查
#ifdef DEBUG
+ (void)judgeExist:(id)obj keyPath:(NSString *)keyPath {
    //检测keyPath
    if (!keyPath || keyPath.length < 1) {
        @throw [NSException exceptionWithName:@"keyPath异常" reason:@"键值为空" userInfo:nil];
    }
    
    NSString *setter = [NSString stringWithFormat:@"set%@%@:",[[keyPath substringToIndex:1] uppercaseString], [keyPath substringFromIndex:1]];
    
    if (!class_getInstanceMethod([obj class], NSSelectorFromString(setter))) {
        @throw [NSException exceptionWithName:@"keyPath异常" reason:[NSString stringWithFormat:@"%@不存在键值为%@的setter或getter方法", NSStringFromClass([obj class]), setter] userInfo:nil];
    }
    
    //检测类型
    const char *encoding = method_getTypeEncoding(class_getInstanceMethod([obj class], NSSelectorFromString(setter)));
    LSEncodingType type = 0;
    IMP imp = getTypeEncodingImp(encoding, &type);
    if (!imp) {
        @throw [NSException exceptionWithName:@"监听类型出错" reason:@"不支持的监听类型自定义struct结构体, union联合体, c类型数组[]" userInfo:nil];
    }
}
#endif

@end
