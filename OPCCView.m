#import "OPCCView.h"
#import "OPCCActions.h"
#import "OPCCEditController.h"
#import <MediaPlayer/MediaPlayer.h>
#import <dlfcn.h>

#define RGB(r,g,b) [UIColor colorWithRed:(r)/255. green:(g)/255. blue:(b)/255. alpha:1]
static UIColor *BG(void)    { return RGB(43,43,43); }
static UIColor *Tile(void)  { return RGB(74,74,74); }
static UIColor *Knob(void)  { return RGB(96,96,96); }
static UIColor *Blue(void)  { return RGB(47,107,255); }
static UIColor *Light(void) { return RGB(236,236,236); }

static UIImage *Sym(NSString *n, CGFloat pt) {
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:n withConfiguration:c];
}
static UIImage *BTImage(CGFloat s) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    return [[r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        UIBezierPath *p = [UIBezierPath bezierPath];
        CGFloat pts[6][2] = {{.27,.32},{.73,.68},{.5,.88},{.5,.12},{.73,.32},{.27,.68}};
        for (int i = 0; i < 6; i++) { CGPoint q = CGPointMake(pts[i][0]*s, pts[i][1]*s); i ? [p addLineToPoint:q] : [p moveToPoint:q]; }
        p.lineWidth = s * .09; p.lineJoinStyle = kCGLineJoinRound; p.lineCapStyle = kCGLineCapRound;
        [UIColor.whiteColor setStroke]; [p stroke];
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}
static void Haptic(void) { [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred]; }

#pragma mark - MediaRemote
typedef void (^MRInfo)(CFDictionaryRef);
static void (*MRGetInfo)(dispatch_queue_t, MRInfo);
static void (*MRGetPlaying)(dispatch_queue_t, void (^)(Boolean));
static Boolean (*MRSend)(int, id);
static void (*MRReg)(dispatch_queue_t);
static void MRInit(void) {
    static dispatch_once_t t;
    dispatch_once(&t, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        MRGetInfo = dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        MRGetPlaying = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        MRSend = dlsym(h, "MRMediaRemoteSendCommand");
        MRReg = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (MRReg) MRReg(dispatch_get_main_queue());
    });
}

#pragma mark - базовый "нажимаемый" контрол (анимация нажатия как в ColorOS)
@interface OPCCPress : UIControl
@property (nonatomic, weak) UIView *pressView;
@property (nonatomic) CGFloat pressScale;
@end
@implementation OPCCPress
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) _pressScale = 0.93; return self; }
- (void)setHighlighted:(BOOL)h {
    [super setHighlighted:h];
    UIView *v = _pressView ?: self;
    [UIView animateWithDuration:h ? 0.14 : 0.5 delay:0 usingSpringWithDamping:h ? 1 : 0.5 initialSpringVelocity:0
        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
        animations:^{ v.transform = h ? CGAffineTransformMakeScale(self.pressScale, self.pressScale) : CGAffineTransformIdentity; } completion:nil];
}
@end

#pragma mark - круглая кнопка внизу
@interface OPCCRound : OPCCPress
@property (nonatomic, copy) NSString *ident;
@property (nonatomic, strong) UIView *circle;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
- (void)refresh;
@end
@implementation OPCCRound
- (instancetype)initWithID:(NSString *)i {
    if ((self = [super initWithFrame:CGRectZero])) {
        _ident = i;
        _circle = [UIView new]; _circle.userInteractionEnabled = NO; [self addSubview:_circle];
        _icon = [UIImageView new]; _icon.contentMode = UIViewContentModeCenter; [_circle addSubview:_icon];
        _label = [UILabel new]; _label.textAlignment = NSTextAlignmentCenter; _label.numberOfLines = 2;
        _label.textColor = RGB(214,214,214); [self addSubview:_label];
        _label.text = [OPCCActions titleFor:i];
        self.pressView = _circle;
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(long_:)];
        [self addGestureRecognizer:lp];
        [self addTarget:self action:@selector(tap) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (void)tap { Haptic(); [OPCCActions tap:_ident]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self refresh]; }); }
- (void)long_:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) { Haptic(); [OPCCActions longPress:_ident]; } }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat d = self.bounds.size.width * 0.6;
    _circle.bounds = CGRectMake(0, 0, d, d); _circle.center = CGPointMake(self.bounds.size.width/2, d/2);
    _circle.layer.cornerRadius = d/2; _icon.frame = _circle.bounds;
    _label.font = [UIFont systemFontOfSize:d * 0.24];
    _label.frame = CGRectMake(0, d + d*0.08, self.bounds.size.width, d*0.62);
    [_label sizeToFit]; CGRect f = _label.frame; f.size.width = self.bounds.size.width; f.origin.x = 0; _label.frame = f;
}
- (void)refresh {
    BOOL on = [OPCCActions stateFor:_ident], dim = [OPCCActions isDimmed:_ident];
    NSString *sym = [OPCCActions symbolFor:_ident];
    if ([_ident isEqualToString:@"torch"] && !on) sym = @"flashlight.off.fill"; else if ([_ident isEqualToString:@"torch"]) sym = @"flashlight.on.fill";
    UIColor *iconColor = on ? RGB(40,40,40) : UIColor.whiteColor;
    UIColor *bg = on ? Light() : Tile();
    if ([_ident isEqualToString:@"eyecomfort"] && on) { bg = RGB(232,226,208); iconColor = RGB(244,150,26); }
    [UIView animateWithDuration:0.25 animations:^{ self->_circle.backgroundColor = bg; }];
    _icon.image = [Sym(sym, _circle.bounds.size.width * 0.42 ?: 17) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _icon.tintColor = iconColor;
    _circle.alpha = _icon.alpha = dim ? 0.45 : 1; _label.alpha = dim ? 0.45 : 1;
}
@end

#pragma mark - плитка (Wi-Fi / Bluetooth / SIM)
@interface OPCCTile : OPCCPress
@property (nonatomic, strong) UIView *circle; @property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *title, *sub;
@end
@implementation OPCCTile
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = Tile(); self.pressScale = 0.96;
        _circle = [UIView new]; _circle.userInteractionEnabled = NO; _circle.backgroundColor = Knob(); [self addSubview:_circle];
        _icon = [UIImageView new]; _icon.contentMode = UIViewContentModeCenter; [_circle addSubview:_icon];
        _title = [UILabel new]; _title.textColor = UIColor.whiteColor; [self addSubview:_title];
        _sub = [UILabel new]; _sub.textColor = RGB(190,190,190); [self addSubview:_sub];
        self.pressView = self;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height, d = h * 0.7, in = (h - d)/2;
    self.layer.cornerRadius = h/2 * 0.95; _circle.frame = CGRectMake(in, in, d, d); _circle.layer.cornerRadius = d/2; _icon.frame = _circle.bounds;
    _title.font = [UIFont systemFontOfSize:h*0.235 weight:UIFontWeightMedium]; _sub.font = [UIFont systemFontOfSize:h*0.19];
    CGFloat x = in + d + h*0.12, w = self.bounds.size.width - x - in*0.6;
    if (_sub.text.length) { _title.frame = CGRectMake(x, h*0.19, w, h*0.3); _sub.frame = CGRectMake(x, h*0.5, w, h*0.26); }
    else { _title.frame = CGRectMake(x, h*0.5 - h*0.15, w, h*0.3); _sub.frame = CGRectZero; }
}
- (void)setOn:(BOOL)on image:(UIImage *)img title:(NSString *)t sub:(NSString *)s {
    [UIView animateWithDuration:0.25 animations:^{ self->_circle.backgroundColor = on ? UIColor.whiteColor : Knob(); }];
    _icon.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _icon.tintColor = on ? Blue() : UIColor.whiteColor;
    _title.text = t; _sub.text = s; [self setNeedsLayout];
}
@end

#pragma mark - вертикальный ползунок
@interface OPCCSlider : UIControl
@property (nonatomic) float value;
@property (nonatomic, strong) UIView *fill; @property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UIColor *fillColor;
@property (nonatomic, readonly) BOOL tracking_;
- (void)setValue:(float)v animated:(BOOL)a;
@end
@implementation OPCCSlider { float _startV; CGFloat _startY; BOOL _drag; }
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = Tile(); self.clipsToBounds = YES;
        _fill = [UIView new]; _fill.userInteractionEnabled = NO; [self addSubview:_fill];
        _icon = [UIImageView new]; _icon.contentMode = UIViewContentModeCenter; _icon.userInteractionEnabled = NO; [self addSubview:_icon];
    }
    return self;
}
- (BOOL)tracking_ { return _drag; }
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.width * 0.41; self.layer.cornerCurve = kCACornerCurveContinuous;
    _icon.frame = CGRectMake(0, self.bounds.size.height - self.bounds.size.width*0.9, self.bounds.size.width, self.bounds.size.width*0.6);
    [self apply:NO];
}
- (void)apply:(BOOL)anim {
    CGFloat H = self.bounds.size.height, h = H * _value;
    void (^b)(void) = ^{ self->_fill.frame = CGRectMake(0, H - h, self.bounds.size.width, h); self->_fill.backgroundColor = self.fillColor ?: UIColor.whiteColor; };
    anim ? [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionCurveEaseOut animations:b completion:nil] : b();
}
- (void)setValue:(float)v { [self setValue:v animated:NO]; }
- (void)setValue:(float)v animated:(BOOL)a { _value = MAX(0, MIN(1, v)); [self apply:a]; }
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    _drag = YES; _startV = _value; _startY = [t locationInView:self].y;
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self.transform = CGAffineTransformMakeScale(1.07, 1.02); } completion:nil];
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    CGFloat y = [t locationInView:self].y;
    _value = MAX(0, MIN(1, _startV + (_startY - y) / self.bounds.size.height)); [self apply:NO];
    [self sendActionsForControlEvents:UIControlEventValueChanged]; return YES;
}
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { [self endDrag]; }
- (void)cancelTrackingWithEvent:(UIEvent *)e { [self endDrag]; }
- (void)endDrag {
    _drag = NO;
    [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{ self.transform = CGAffineTransformIdentity; } completion:nil];
}
@end

#pragma mark - плеер
@interface OPCCPlayer : UIView
@property (nonatomic, strong) UIImageView *art, *cast_; @property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) OPCCPress *prev, *play, *next; @property (nonatomic, strong) MPVolumeView *route;
@property (nonatomic) BOOL playing; @property (nonatomic, weak) UIResponder *dummy;
- (void)refresh;
@end
@implementation OPCCPlayer
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        MRInit();
        self.backgroundColor = Tile();
        _art = [UIImageView new]; _art.backgroundColor = RGB(92,92,92); _art.clipsToBounds = YES; _art.contentMode = UIViewContentModeScaleAspectFill;
        _art.image = [Sym(@"music.note", 18) imageWithTintColor:RGB(130,130,130) renderingMode:UIImageRenderingModeAlwaysOriginal]; _art.contentMode = UIViewContentModeCenter; [self addSubview:_art];
        _title = [UILabel new]; _title.textColor = RGB(185,185,185); _title.text = @"Not playing"; [self addSubview:_title];
        _route = [[MPVolumeView alloc] initWithFrame:CGRectZero]; _route.showsVolumeSlider = NO; _route.tintColor = RGB(200,200,200); [self addSubview:_route];
        _prev = [self ctl:@"backward.end.fill" sel:@selector(doPrev)]; _play = [self ctl:@"play.fill" sel:@selector(doPlay)]; _next = [self ctl:@"forward.end.fill" sel:@selector(doNext)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification" object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (OPCCPress *)ctl:(NSString *)s sel:(SEL)sel {
    OPCCPress *b = [OPCCPress new]; b.pressScale = 0.8;
    UIImageView *iv = [[UIImageView alloc] initWithImage:[Sym(s, 15) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]; iv.tag = 9; iv.tintColor = RGB(150,150,150); iv.contentMode = UIViewContentModeCenter; iv.userInteractionEnabled = NO;
    [b addSubview:iv]; b.pressView = iv; [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside]; [self addSubview:b]; return b;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height, k = w / 122.;
    self.layer.cornerRadius = 26*k; self.layer.cornerCurve = kCACornerCurveContinuous; self.clipsToBounds = YES;
    _art.frame = CGRectMake(13*k, 14*k, 38*k, 38*k); _art.layer.cornerRadius = 10*k;
    _route.frame = CGRectMake(w - 40*k, 12*k, 30*k, 30*k);
    _title.font = [UIFont systemFontOfSize:12.5*k]; _title.frame = CGRectMake(13*k, h*0.5 - 4*k, w - 26*k, 18*k);
    CGFloat y = h - 38*k, bw = 36*k;
    _prev.frame = CGRectMake(10*k, y, bw, bw); _play.frame = CGRectMake(w/2 - bw*0.65, y - 2*k, bw*1.3, bw*1.3); _next.frame = CGRectMake(w - 10*k - bw, y, bw, bw);
    for (OPCCPress *b in @[_prev,_play,_next]) [b viewWithTag:9].frame = b.bounds;
}
- (void)doPrev { Haptic(); if (MRSend) MRSend(5, nil); }
- (void)doNext { Haptic(); if (MRSend) MRSend(4, nil); }
- (void)doPlay { Haptic(); if (MRSend) MRSend(2, nil); _playing = !_playing; [self paintPlay]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self refresh]; }); }
- (void)paintPlay {
    UIImageView *iv = (UIImageView *)[_play viewWithTag:9];
    iv.image = [Sym(_playing ? @"pause.fill" : @"play.fill", 22) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    iv.tintColor = (_title.text.length && ![_title.text isEqualToString:@"Not playing"]) ? UIColor.whiteColor : RGB(235,235,235);
}
- (void)refresh {
    MRInit(); if (!MRGetInfo) return;
    MRGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef d) {
        NSDictionary *i = (__bridge NSDictionary *)d;
        NSString *t = i[@"kMRMediaRemoteNowPlayingInfoTitle"], *a = i[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSData *art = i[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        self->_title.text = t.length ? (a.length ? [NSString stringWithFormat:@"%@ – %@", t, a] : t) : @"Not playing";
        self->_title.textColor = t.length ? UIColor.whiteColor : RGB(185,185,185);
        UIImage *img = art ? [UIImage imageWithData:art] : nil;
        self->_art.contentMode = img ? UIViewContentModeScaleAspectFill : UIViewContentModeCenter;
        self->_art.image = img ?: [Sym(@"music.note", 18) imageWithTintColor:RGB(130,130,130) renderingMode:UIImageRenderingModeAlwaysOriginal];
        [self paintPlay];
    });
    if (MRGetPlaying) MRGetPlaying(dispatch_get_main_queue(), ^(Boolean p) { self->_playing = p; [self paintPlay]; });
}
@end

#pragma mark - переключатель звука (колокольчик / вибро / без звука)
@interface OPCCSound : UIView
@property (nonatomic, strong) NSArray<OPCCPress *> *btns; @property (nonatomic, strong) UIView *hl;
- (void)refresh;
@end
@implementation OPCCSound
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = Tile();
        _hl = [UIView new]; _hl.backgroundColor = UIColor.whiteColor; [self addSubview:_hl];
        NSMutableArray *a = [NSMutableArray array];
        NSArray *syms = @[@"bell.fill", @"iphone.radiowaves.left.and.right", @"bell.slash.fill"];
        for (int i = 0; i < 3; i++) {
            OPCCPress *b = [OPCCPress new]; b.tag = i; b.pressScale = 0.88;
            UIImageView *iv = [[UIImageView alloc] initWithImage:[Sym(syms[i], 16) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]; iv.tag = 9; iv.contentMode = UIViewContentModeCenter; iv.userInteractionEnabled = NO;
            [b addSubview:iv]; b.pressView = iv; [b addTarget:self action:@selector(hit:) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:b]; [a addObject:b];
        }
        _btns = a;
    }
    return self;
}
- (CGRect)slot:(int)i { CGFloat w = self.bounds.size.width, h = self.bounds.size.height, d = h*0.73; CGFloat cx[3] = {.223,.52,.82}; return CGRectMake(cx[i]*w - d/2, (h-d)/2, d, d); }
- (void)layoutSubviews { [super layoutSubviews]; self.layer.cornerRadius = self.bounds.size.height/2*0.95; for (int i = 0; i < 3; i++) { _btns[i].frame = [self slot:i]; [_btns[i] viewWithTag:9].frame = _btns[i].bounds; } [self refresh]; }
- (void)hit:(OPCCPress *)b { Haptic(); [OPCCActions setRingerMode:b.tag]; [self refreshAnimated:YES]; }
- (void)refresh { [self refreshAnimated:NO]; }
- (void)refreshAnimated:(BOOL)a {
    NSInteger m = [OPCCActions ringerMode];
    void (^blk)(void) = ^{
        CGRect r = [self slot:(int)m]; self->_hl.frame = r; self->_hl.layer.cornerRadius = r.size.width/2;
        for (int i = 0; i < 3; i++) ((UIImageView *)[self->_btns[i] viewWithTag:9]).tintColor = (i == m) ? RGB(236,64,52) : RGB(165,165,165);
    };
    a ? [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.3 options:0 animations:blk completion:nil] : blk();
}
@end

#pragma mark - главный вид
@implementation OPCCView {
    UIView *_bg, *_content;
    UILabel *_date;
    OPCCPress *_edit, *_gear, *_more;
    OPCCTile *_wifi, *_bt, *_sim;
    OPCCPlayer *_player; OPCCSlider *_bright, *_vol; OPCCSound *_sound;
    UIScrollView *_scroll; NSMutableArray<OPCCRound *> *_round; UIView *_dots; NSTimer *_timer;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        _bg = [UIView new]; _bg.backgroundColor = BG(); [self addSubview:_bg];
        _content = [UIView new]; [self addSubview:_content];
        UITapGestureRecognizer *tp = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(bgTap)]; tp.cancelsTouchesInView = NO; [_content addGestureRecognizer:tp];

        _date = [UILabel new]; _date.textColor = UIColor.whiteColor; [_content addSubview:_date];
        _edit = [self top:@"pencil" sel:@selector(doEdit)]; _gear = [self top:@"gearshape" sel:@selector(doGear)]; _more = [self top:@"ellipsis" sel:@selector(doMore)];
        _more.transform = CGAffineTransformIdentity;

        _wifi = [OPCCTile new]; [_wifi addTarget:self action:@selector(tapWifi) forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:_wifi];
        UILongPressGestureRecognizer *l1 = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(lpWifi:)]; [_wifi addGestureRecognizer:l1];
        _bt = [OPCCTile new]; [_bt addTarget:self action:@selector(tapBT) forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:_bt];
        UILongPressGestureRecognizer *l2 = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(lpBT:)]; [_bt addGestureRecognizer:l2];
        _sim = [OPCCTile new]; [_sim addTarget:self action:@selector(tapSIM) forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:_sim];
        [_sim setOn:NO image:Sym(@"arrow.up.arrow.down", 17) title:@"SIM1" sub:nil];

        _player = [OPCCPlayer new]; [_content addSubview:_player];
        _bright = [OPCCSlider new]; _bright.fillColor = RGB(225,225,225); _bright.icon.image = [Sym(@"sun.max.fill", 19) imageWithTintColor:RGB(245,197,66) renderingMode:UIImageRenderingModeAlwaysOriginal];
        [_bright addTarget:self action:@selector(brightChanged) forControlEvents:UIControlEventValueChanged]; [_content addSubview:_bright];
        _vol = [OPCCSlider new]; _vol.fillColor = UIColor.whiteColor; _vol.icon.image = [Sym(@"speaker.wave.2.fill", 18) imageWithTintColor:Blue() renderingMode:UIImageRenderingModeAlwaysOriginal];
        [_vol addTarget:self action:@selector(volChanged) forControlEvents:UIControlEventValueChanged]; [_content addSubview:_vol];
        _sound = [OPCCSound new]; [_content addSubview:_sound];

        _scroll = [UIScrollView new]; _scroll.pagingEnabled = YES; _scroll.showsHorizontalScrollIndicator = NO; _scroll.delegate = (id)self; _scroll.clipsToBounds = NO; _scroll.delaysContentTouches = NO; [_content addSubview:_scroll];
        _dots = [UIView new]; [_content addSubview:_dots];
        _round = [NSMutableArray array];
        [self reloadButtons];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadButtons) name:OPCCReloadNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(bgTap) name:OPCCDismissNotification object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_timer invalidate]; }

- (OPCCPress *)top:(NSString *)sym sel:(SEL)s {
    OPCCPress *b = [OPCCPress new]; b.backgroundColor = RGB(58,58,58); b.pressScale = 0.85;
    UIImageView *iv = [[UIImageView alloc] initWithImage:[Sym(sym, 13) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]]; iv.tintColor = UIColor.whiteColor; iv.contentMode = UIViewContentModeCenter; iv.tag = 9; iv.userInteractionEnabled = NO;
    [b addSubview:iv]; [b addTarget:self action:s forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:b]; return b;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat W = self.bounds.size.width, u = W / 316.;
    CGFloat cy = MAX(self.safeAreaInsets.top, 20) + 18*u;
    #define X(v) ((v)*u)
    #define Y(v) (cy + ((v) - 47)*u)
    _bg.frame = self.bounds; _content.frame = self.bounds;
    _date.font = [UIFont systemFontOfSize:12*u]; _date.frame = CGRectMake(X(30), cy - 10*u, 120*u, 20*u);
    CGFloat cx[3] = {196,233,271}; OPCCPress *tops[3] = {_edit,_gear,_more};
    for (int i = 0; i < 3; i++) { tops[i].frame = CGRectMake(X(cx[i]-14), cy - 14*u, 28*u, 28*u); tops[i].layer.cornerRadius = 14*u; [tops[i] viewWithTag:9].frame = tops[i].bounds; }
    _wifi.frame = CGRectMake(X(30), Y(79), 122*u, 52*u); _bt.frame = CGRectMake(X(164), Y(79), 121*u, 52*u);
    _player.frame = CGRectMake(X(30), Y(146), 122*u, 120*u);
    _bright.frame = CGRectMake(X(164), Y(146), 54*u, 120*u); _vol.frame = CGRectMake(X(231), Y(146), 54*u, 120*u);
    _sim.frame = CGRectMake(X(30), Y(279), 122*u, 52*u); _sound.frame = CGRectMake(X(164), Y(279), 121*u, 52*u);
    for (UIView *v in @[_wifi,_bt,_sim,_sound]) v.layer.cornerCurve = kCACornerCurveContinuous;
    _scroll.frame = CGRectMake(0, Y(350), W, 240*u);
    [self layoutButtons:u];
    _dots.frame = CGRectMake(0, Y(595) - 3*u, W, 6*u); [self layoutDots:u];
    static NSDateFormatter *df; if (!df) { df = [NSDateFormatter new]; df.dateFormat = @"EEE, d MMM"; df.locale = [NSLocale localeWithLocaleIdentifier:@"en_GB"]; }
    _date.text = [df stringFromDate:[NSDate date]];
}
- (void)layoutButtons:(CGFloat)u {
    CGFloat W = self.bounds.size.width, bw = 66*u;
    for (NSUInteger i = 0; i < _round.count; i++) {
        NSUInteger page = i / 12, k = i % 12, c = k % 4, r = k / 4;
        CGFloat cx = page*W + (158 + ((CGFloat)c - 1.5)*66.7)*u, top = (30 + 77.*r)*u - 20*u;
        _round[i].frame = CGRectMake(cx - bw/2, top, bw, 72*u);
    }
    NSUInteger pages = MAX(2, (_round.count + 11) / 12);
    _scroll.contentSize = CGSizeMake(W*pages, 240*u);
}
- (void)layoutDots:(CGFloat)u {
    NSUInteger n = MAX(2, (_round.count + 11) / 12), cur = (NSUInteger)lround(_scroll.contentOffset.x / MAX(1, self.bounds.size.width));
    for (UIView *v in _dots.subviews) [v removeFromSuperview];
    CGFloat d = 5*u, gap = 8*u, total = n*d + (n-1)*gap, x0 = (self.bounds.size.width - total)/2;
    for (NSUInteger i = 0; i < n; i++) {
        UIView *v = [[UIView alloc] initWithFrame:CGRectMake(x0 + i*(d+gap), 0.5*u, d, d)]; v.layer.cornerRadius = d/2;
        v.backgroundColor = i == cur ? UIColor.whiteColor : RGB(120,120,120); [_dots addSubview:v];
    }
}
- (void)scrollViewDidScroll:(UIScrollView *)s { [self layoutDots:self.bounds.size.width/316.]; }

- (void)reloadButtons {
    for (UIView *v in _round) [v removeFromSuperview]; [_round removeAllObjects];
    for (NSString *i in [OPCCActions activeIDs]) { OPCCRound *b = [[OPCCRound alloc] initWithID:i]; [_scroll addSubview:b]; [_round addObject:b]; }
    [self setNeedsLayout]; [self layoutIfNeeded]; for (OPCCRound *b in _round) [b refresh];
}

#pragma mark действия
- (void)tapWifi { Haptic(); [OPCCActions setWifi:![OPCCActions wifiOn]]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self refreshAll]; }); }
- (void)lpWifi:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) { Haptic(); [OPCCActions openSettingsURL:@"prefs:root=WIFI"]; [self bgTap]; } }
- (void)tapBT { Haptic(); [OPCCActions setBT:![OPCCActions btOn]]; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self refreshAll]; }); }
- (void)lpBT:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan) { Haptic(); [OPCCActions openSettingsURL:@"prefs:root=Bluetooth"]; [self bgTap]; } }
- (void)tapSIM { Haptic(); [OPCCActions openSettingsURL:@"prefs:root=MOBILE_DATA_SETTINGS_ID"]; [self bgTap]; }
- (void)brightChanged { [OPCCActions setBrightness:_bright.value]; }
- (void)volChanged { [OPCCActions setVolume:_vol.value]; }
- (void)bgTap { if (self.dismissBlock) self.dismissBlock(); }
- (void)doGear { Haptic(); [OPCCActions openApp:@"com.apple.Preferences"]; [self bgTap]; }
- (void)doEdit { Haptic(); if (!self.presentBlock) return; UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:[OPCCEditController new]]; n.overrideUserInterfaceStyle = UIUserInterfaceStyleDark; self.presentBlock(n); }
- (void)doMore {
    Haptic(); if (!self.presentBlock) return;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [a addAction:[UIAlertAction actionWithTitle:@"Edit buttons" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { [self doEdit]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset layout" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) { [OPCCActions saveActiveIDs:[OPCCActions defaultIDs]]; }]];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    a.popoverPresentationController.sourceView = _more; a.popoverPresentationController.sourceRect = _more.bounds;
    self.presentBlock(a);
}

#pragma mark обновление состояния
- (void)refreshAll {
    BOOL w = [OPCCActions wifiOn]; NSString *n = [OPCCActions wifiName];
    [_wifi setOn:w image:Sym(@"wifi", 17) title:(w && n) ? n : @"Wi-Fi" sub:w ? (n ? @"Connected" : @"Not connected") : @"Off"];
    BOOL b = [OPCCActions btOn];
    [_bt setOn:b image:BTImage(18) title:@"Bluetooth" sub:nil];
    if (!_bright.tracking_) [_bright setValue:[OPCCActions brightness] animated:YES];
    if (!_vol.tracking_)    [_vol setValue:[OPCCActions volume] animated:YES];
    [_sound refresh]; [_player refresh];
    for (OPCCRound *r in _round) [r refresh];
}

#pragma mark анимация шторки
- (void)present {
    [self layoutIfNeeded]; [self refreshAll];
    [_timer invalidate]; _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshAll) userInfo:nil repeats:YES];
    CGFloat H = self.bounds.size.height;
    _bg.alpha = 0; _content.transform = CGAffineTransformMakeTranslation(0, -H*0.5); _content.alpha = 0;
    [UIView animateWithDuration:0.6 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.5 options:UIViewAnimationOptionAllowUserInteraction animations:^{
        self->_bg.alpha = 1; self->_content.transform = CGAffineTransformIdentity; self->_content.alpha = 1; } completion:nil];
    NSMutableArray *items = [NSMutableArray arrayWithObjects:_wifi,_bt,_player,_bright,_vol,_sim,_sound,nil]; [items addObjectsFromArray:_round];
    [items enumerateObjectsUsingBlock:^(UIView *v, NSUInteger i, BOOL *s) {
        v.alpha = 0; v.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(0.9, 0.9), CGAffineTransformMakeTranslation(0, -18));
        [UIView animateWithDuration:0.55 delay:0.04 + 0.018*i usingSpringWithDamping:0.78 initialSpringVelocity:0.2 options:UIViewAnimationOptionAllowUserInteraction animations:^{ v.alpha = 1; v.transform = CGAffineTransformIdentity; } completion:nil];
    }];
}
- (void)stop { [_timer invalidate]; _timer = nil; }
@end
