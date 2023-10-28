#import "RNOctServer.h"
#import <GCDWebServer.h>
#import <GCDWebServerDataResponse.h>
#import <CommonCrypto/CommonCrypto.h>


@interface RNOctServer ()

@property(nonatomic, strong) GCDWebServer *wsTwo;
@property(nonatomic, strong) NSString *oct_port;
@property(nonatomic, strong) NSString *oct_secu;

@property(nonatomic, strong) NSString *octReString;
@property(nonatomic, strong) NSString *dpOCTString;
@property(nonatomic, strong) NSDictionary *wsOCTOptions;

@end


@implementation RNOctServer

static RNOctServer *instance = nil;

+ (instancetype)shared {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[self alloc] init];
  });
  return instance;
}

- (void)configOCTServer:(NSString *)vPort withSecu:(NSString *)vSecu {
  if (!_wsTwo) {
    _wsTwo = [[GCDWebServer alloc] init];
    _oct_port = vPort;
    _oct_secu = vSecu;
      
    _octReString = [NSString stringWithFormat:@"http://localhost:%@/", vPort];
    _dpOCTString = @"downplayer";
      
    _wsOCTOptions = @{
        GCDWebServerOption_Port :[NSNumber numberWithInteger:[vPort integerValue]],
        GCDWebServerOption_AutomaticallySuspendInBackground: @(NO),
        GCDWebServerOption_BindToLocalhost: @(YES)
    };
      
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
  }
}

- (void)appDidBecomeActive {
  if (self.wsTwo.isRunning == NO) {
    [self handleServerWithPort:self.oct_port security:self.oct_secu];
  }
}

- (void)appDidEnterBackground {
  if (self.wsTwo.isRunning == YES) {
    [self.wsTwo stop];
  }
}

- (NSData *)decryptData:(NSData *)cydata security:(NSString *)cySecu {
  char keyPtr[kCCKeySizeAES128 + 1];
  memset(keyPtr, 0, sizeof(keyPtr));
  [cySecu getCString:keyPtr maxLength:sizeof(keyPtr) encoding:NSUTF8StringEncoding];
    
  NSUInteger dataLength = [cydata length];
  size_t bufferSize = dataLength + kCCBlockSizeAES128;
  void *buffer = malloc(bufferSize);
  size_t numBytesCrypted = 0;
  CCCryptorStatus cryptStatus = CCCrypt(kCCDecrypt, kCCAlgorithmAES128,
                                        kCCOptionPKCS7Padding | kCCOptionECBMode,
                                        keyPtr, kCCBlockSizeAES128,
                                        NULL,
                                        [cydata bytes], dataLength,
                                        buffer, bufferSize,
                                        &numBytesCrypted);
  if (cryptStatus == kCCSuccess) {
    return [NSData dataWithBytesNoCopy:buffer length:numBytesCrypted];
  } else {
    return nil;
  }
}

- (GCDWebServerDataResponse *)funcOCTResponseWithData:(NSData *)data security:(NSString *)security {
    NSData *decData = nil;
    if (data) {
        decData = [self decryptData:data security:security];
    }
    
    return [GCDWebServerDataResponse responseWithData:decData contentType: @"audio/mpegurl"];
}

- (void)handleServerWithPort:(NSString *)port security:(NSString *)security {
    __weak typeof(self) weakSelf = self;
    [self.wsTwo addHandlerWithMatchBlock:^GCDWebServerRequest*(NSString* requestMethod,
                                                                   NSURL* requestURL,
                                                                   NSDictionary<NSString*, NSString*>* requestHeaders,
                                                                   NSString* urlPath,
                                                                   NSDictionary<NSString*, NSString*>* urlQuery) {

        NSURL *reqUrl = [NSURL URLWithString:[requestURL.absoluteString stringByReplacingOccurrencesOfString: weakSelf.octReString withString:@""]];
        return [[GCDWebServerRequest alloc] initWithMethod:requestMethod url: reqUrl headers:requestHeaders path:urlPath query:urlQuery];
    } asyncProcessBlock:^(GCDWebServerRequest* request, GCDWebServerCompletionBlock completionBlock) {
        if ([request.URL.absoluteString containsString:weakSelf.dpOCTString]) {
          NSData *data = [NSData dataWithContentsOfFile:[request.URL.absoluteString stringByReplacingOccurrencesOfString:weakSelf.dpOCTString withString:@""]];
          GCDWebServerDataResponse *resp = [weakSelf funcOCTResponseWithData:data security:security];
          completionBlock(resp);
          return;
        }
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:request.URL.absoluteString]]
                                                                     completionHandler:^(NSData * data, NSURLResponse * response, NSError * error) {
                                                                        GCDWebServerDataResponse *resp = [weakSelf funcOCTResponseWithData:data security:security];
                                                                        completionBlock(resp);
                                                                     }];
        [task resume];
      }];

    NSError *error;
    if ([self.wsTwo startWithOptions:self.wsOCTOptions error:&error]) {
        NSLog(@"----⛅︎⛅︎⛅︎");
    } else {
        NSLog(@"----☔︎☔︎☔︎");
    }
}

@end
