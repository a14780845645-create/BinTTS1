#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/**
 * 微信 TTS 插件 (WeChat TTS Plugin)
 * 核心逻辑：
 * 1. Hook 微信聊天界面，添加 TTS 按钮。
 * 2. 弹出音色选择和文字输入框。
 * 3. 调用 Fish Audio API 获取 MP3。
 * 4. 将 MP3 转换为 Silk (微信专用格式)。
 * 5. Hook 微信发送逻辑，注入 Silk 文件并发送。
 */

// --- 微信内部类声明 ---
@interface CMessageMgr : NSObject
- (void)AddMsg:(id)arg1 MsgData:(id)arg2;
@end

@interface MMServiceCenter : NSObject
+ (id)defaultCenter;
- (id)getService:(Class)arg1;
@end

@interface CContact : NSObject
@property(retain, nonatomic) NSString *m_nsUsrName;
@end

@interface BaseMsgContentViewController : UIViewController
@property(retain, nonatomic) CContact *m_contact;
@end

// --- 插件状态管理 ---
static NSString *const kFishAudioAPIKey = @"9a01e5b92d2e4c868806c65ec0d93f52"; // 建议通过设置界面动态获取
static NSString *const kFishAudioURL = @"https://api.fish.audio/v1/tts";

@interface TTSService : NSObject
+ (instancetype)sharedInstance;
- (void)sendTTSWithText:(NSString *)text voiceID:(NSString *)voiceID toUser:(NSString *)username;
@end

@implementation TTSService

+ (instancetype)sharedInstance {
    static TTSService *service = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        service = [[TTSService alloc] init];
    });
    return service;
}

- (void)sendTTSWithText:(NSString *)text voiceID:(NSString *)voiceID toUser:(NSString *)username {
    // 1. 构造请求参数 (参考用户提供的 tts.php)
    NSDictionary *payload = @{
        @"text": text,
        @"reference_id": voiceID,
        @"format": @"mp3",
        @"sample_rate": @44100,
        @"mp3_bitrate": @128,
        @"speed": @1.0,
        @"pitch": @1.0,
        @"volume": @1.0
    };

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kFishAudioURL]];
    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", kFishAudioAPIKey] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data) {
            NSLog(@"[TTS] 请求失败: %@", error);
            return;
        }

        // 2. 保存 MP3 到临时目录
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tts_temp.mp3"];
        [data writeToFile:tempPath atomically:YES];

        // 3. 转换为 Silk 格式 (这里需要集成 libsilk 转换库)
        // 注意：微信内部也有转换逻辑，通常我们会调用封装好的 libsilk.dylib
        NSString *silkPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tts_temp.silk"];
        BOOL success = [self convertMP3ToSilk:tempPath outputPath:silkPath];

        if (success) {
            // 4. 调用微信发送逻辑
            [self sendSilkFile:silkPath toUser:username];
        }
    }] resume];
}

- (BOOL)convertMP3ToSilk:(NSString *)inputPath outputPath:(NSString *)outputPath {
    // 实际开发中需要集成具体的 Silk 编码器
    // 示例逻辑：调用外部转换工具或库
    NSLog(@"[TTS] 正在转换 MP3 到 Silk: %@ -> %@", inputPath, outputPath);
    // 这里假设转换成功，实际代码需调用具体转换函数
    return YES; 
}

- (void)sendSilkFile:(NSString *)filePath toUser:(NSString *)username {
    // Hook 微信发送语音的核心逻辑
    // 微信发送语音通常涉及 AudioMsgMgr 和 CMessageMgr
    // 1. 创建语音消息对象
    // 2. 设置文件路径和时长
    // 3. 调用 AddMsg 发送
    NSLog(@"[TTS] 正在发送语音文件到用户: %@", username);
}

@end

// --- Hook 微信界面 ---

%hook BaseMsgContentViewController

- (void)viewDidLoad {
    %orig;
    
    // 在界面上添加一个 TTS 按钮 (示例：添加在导航栏右侧)
    UIBarButtonItem *ttsItem = [[UIBarButtonItem alloc] initWithTitle:@"TTS" 
                                                               style:UIBarButtonItemStylePlain 
                                                              target:self 
                                                              action:@selector(handleTTSClick)];
    self.navigationItem.rightBarButtonItems = @[ttsItem];
}

%new
- (void)handleTTSClick {
    // 弹出输入框
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"文字转语音" 
                                                                   message:@"请输入要转换的文字" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"输入文字...";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields.firstObject.text;
        if (text.length > 0) {
            // 这里默认使用一个测试音色 ID，实际应从 quanming.json 中选择
            NSString *testVoiceID = @"ad1385dc137145bf93e95a6272fbb34a"; // AI步非烟
            [[TTSService sharedInstance] sendTTSWithText:text 
                                                 voiceID:testVoiceID 
                                                  toUser:self.m_contact.m_nsUsrName];
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

%end
