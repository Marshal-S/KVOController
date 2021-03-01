    /*
     注意: 只有属性才支持监听，即有setter和getter方法，想获取旧值必须有getter方法
     不支持的监听类型,包括自定义struct结构体，union联合体, c类型数组[]，或者其他未知结构
     id对象返回的还是对象
     NSNumber、Class、SEL、Pointer(指针类型)、char *返回的均为NSValue类型
     同一个键值、同一个观察者只能有一个回调，后添加的覆盖先前的
     */
     
    ```
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
        @property CGVector vecor;
        @property CGAffineTransform trans;
        @property UIEdgeInsets insets;
        @property UIOffset offset;
        @property NSRange range;
        @property NSDirectionalEdgeInsets dirInset;

        @property LSDog *dog;

    @end
    
    @interface LSDog : NSObject

        @property NSString *name;

        @property NSInteger age;

        @property NSString *color;

    @end
    ```
    
    
    # ViewController
    
    添加监听
    ```
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
    ```
    
    设置回调
    ```
    self.student.name = @"小明";
    self.student.age = 29;
    
    int *a = (int *)malloc(sizeof(int));
    *a = 10;
    self.student.point = a;
    
    self.student.cls = NSClassFromString(@"ViewController");
    self.student.sel = @selector(onDelete:);
    ```
    
    打印内容
    ```
    self.student.name = @"小明";
    self.student.age = 29;

    int *a = (int *)malloc(sizeof(int));
    *a = 10;
    self.student.pointer = a;

    self.student.cls = NSClassFromString(@"ViewController");
    self.student.sel = @selector(onDelete:);
    
    self.student.rect = CGRectMake(0, 0, 0, 0);
    
    [self.student setBlock:^(int a) {
        NSLog(@"测试一下了: %d", a);
    }];
    
    self.student.dog.color = @"红色";
    self.student.dog.name = @"毛毛";
    self.student.dog.age = 2;
    ```



