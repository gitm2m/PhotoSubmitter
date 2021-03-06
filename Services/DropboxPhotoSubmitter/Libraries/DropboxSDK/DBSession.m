//
//  DBSession.m
//  DropboxSDK
//
//  Created by Brian Smith on 4/8/10.
//  Copyright 2010 Dropbox, Inc. All rights reserved.
//
#if __has_feature(objc_arc)
#error This file must be compiled with Non-ARC. use -fno-objc_arc flag (or convert project to Non-ARC)
#endif

#import "DBSession.h"

#import <CommonCrypto/CommonDigest.h>

#import "DBLog.h"
#import "MPOAuthCredentialConcreteStore.h"
#import "MPOAuthSignatureParameter.h"

NSString *kDBSDKVersion = @"1.1"; // TODO: parameterize from build system

NSString *kDBDropboxAPIHost = @"api.dropbox.com";
NSString *kDBDropboxAPIContentHost = @"api-content.dropbox.com";
NSString *kDBDropboxWebHost = @"www.dropbox.com";
NSString *kDBDropboxAPIVersion = @"1";

NSString *kDBRootDropbox = @"dropbox";
NSString *kDBRootAppFolder = @"sandbox";

NSString *kDBProtocolHTTPS = @"https";

static NSString *kDBProtocolDropbox = @"dbapi-1";

static DBSession *_sharedSession = nil;
static NSString *kDBDropboxSavedCredentialsOld = @"kDBDropboxSavedCredentialsKey";
static NSString *kDBDropboxSavedCredentials = @"kDBDropboxSavedCredentials";
static NSString *kDBDropboxUserCredentials = @"kDBDropboxUserCredentials";
static NSString *kDBDropboxUserId = @"kDBDropboxUserId";
static NSString *kDBDropboxUnknownUserId = @"unknown";


@interface DBSession ()

- (NSDictionary*)savedCredentials;
- (void)saveCredentials;
- (void)clearSavedCredentials;
- (void)setAccessToken:(NSString *)token accessTokenSecret:(NSString *)secret forUserId:(NSString *)userId;
- (NSString *)appScheme;
- (BOOL)appConformsToScheme;

@end


@implementation DBSession

+ (DBSession *)sharedSession {
    return _sharedSession;
}

+ (void)setSharedSession:(DBSession *)session {
    if (session == _sharedSession) return;
    [_sharedSession release];
    _sharedSession = [session retain];
}

- (id)initWithAppKey:(NSString *)key appSecret:(NSString *)secret root:(NSString *)theRoot {
    if ((self = [super init])) {
        
        baseCredentials = 
            [[NSDictionary alloc] initWithObjectsAndKeys:
                key, kMPOAuthCredentialConsumerKey,
                secret, kMPOAuthCredentialConsumerSecret, 
                kMPOAuthSignatureMethodPlaintext, kMPOAuthSignatureMethod, nil];
                
        credentialStores = [NSMutableDictionary new];
        
        NSDictionary *oldSavedCredentials =
            [[NSUserDefaults standardUserDefaults] objectForKey:kDBDropboxSavedCredentialsOld];
        if (oldSavedCredentials) {
            if ([key isEqual:[oldSavedCredentials objectForKey:kMPOAuthCredentialConsumerKey]]) {
                NSString *token = [oldSavedCredentials objectForKey:kMPOAuthCredentialAccessToken];
                NSString *secret = [oldSavedCredentials objectForKey:kMPOAuthCredentialAccessTokenSecret];
                [self setAccessToken:token accessTokenSecret:secret forUserId:kDBDropboxUnknownUserId];
            }
        }
        
        NSDictionary *savedCredentials = [self savedCredentials];
        if (savedCredentials != nil) {
            if ([key isEqualToString:[savedCredentials objectForKey:kMPOAuthCredentialConsumerKey]]) {
            
                NSArray *allUserCredentials = [savedCredentials objectForKey:kDBDropboxUserCredentials];
                for (NSDictionary *userCredentials in allUserCredentials) {
                    NSString *userId = [userCredentials objectForKey:kDBDropboxUserId];
                    NSString *token = [userCredentials objectForKey:kMPOAuthCredentialAccessToken];
                    NSString *secret = [userCredentials objectForKey:kMPOAuthCredentialAccessTokenSecret];
                    [self setAccessToken:token accessTokenSecret:secret forUserId:userId];
                }
            } else {
                [self clearSavedCredentials];
            }
        }
        
        root = [theRoot retain];
    }
    return self;
}

- (void)dealloc {
    [baseCredentials release];
    [credentialStores release];
    [root release];
    [super dealloc];
}

@synthesize root;
@synthesize delegate;

- (void)updateAccessToken:(NSString *)token accessTokenSecret:(NSString *)secret forUserId:(NSString *)userId {
    [self setAccessToken:token accessTokenSecret:secret forUserId:userId];
    [self saveCredentials];
}

- (void)setAccessToken:(NSString *)token accessTokenSecret:(NSString *)secret forUserId:(NSString *)userId {
    MPOAuthCredentialConcreteStore *credentialStore = [credentialStores objectForKey:userId];
    if (!credentialStore) {
        credentialStore = 
            [[MPOAuthCredentialConcreteStore alloc] initWithCredentials:baseCredentials];
        [credentialStores setObject:credentialStore forKey:userId];
        [credentialStore release];
        
        if (![userId isEqual:kDBDropboxUnknownUserId] && [credentialStores objectForKey:kDBDropboxUnknownUserId]) {
            // If the unknown user is in credential store, replace it with this new entry
            [credentialStores removeObjectForKey:kDBDropboxUnknownUserId];
        }
    }
    credentialStore.accessToken = token;
    credentialStore.accessTokenSecret = secret;
}

- (BOOL)isLinked {
    return [credentialStores count] != 0;
}

- (void)linkUserId:(NSString *)userId {
    if (![self appConformsToScheme]) {
        DBLogError(@"DropboxSDK: unable to link; app isn't registered for correct URL scheme (%@)", [self appScheme]);
        return;
    }

    NSString *userIdStr = @"";
    if (userId && ![userId isEqual:kDBDropboxUnknownUserId]) {
        userIdStr = [NSString stringWithFormat:@"&u=%@", userId];
    }
    
    NSString *consumerKey = [baseCredentials objectForKey:kMPOAuthCredentialConsumerKey];
    
    NSData *consumerSecret = 
        [[baseCredentials objectForKey:kMPOAuthCredentialConsumerSecret] dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char md[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(consumerSecret.bytes, [consumerSecret length], md);
    NSUInteger sha_32 = htonl(((NSUInteger *)md)[CC_SHA1_DIGEST_LENGTH/sizeof(NSUInteger) - 1]);
    NSString *secret = [NSString stringWithFormat:@"%x", sha_32];
    
    NSString *urlStr = nil;
    
    NSURL *dbURL =
        [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/connect", kDBProtocolDropbox, kDBDropboxAPIVersion]];
    if ([[UIApplication sharedApplication] canOpenURL:dbURL]) {
        urlStr = [NSString stringWithFormat:@"%@?k=%@&s=%@%@", dbURL, consumerKey, secret, userIdStr];
    } else {
        urlStr = [NSString stringWithFormat:@"%@://%@/%@/connect?k=%@&s=%@%@", 
            kDBProtocolHTTPS, kDBDropboxWebHost, kDBDropboxAPIVersion, consumerKey, secret, userIdStr];
    }
    
    [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlStr]];
}

- (void)link {
    [self linkUserId:nil];
}    

/* A private function for parsing URL parameters. */
- (NSDictionary*)parseURLParams:(NSString *)query {
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSMutableDictionary *params = [[[NSMutableDictionary alloc] init] autorelease];
    for (NSString *pair in pairs) {
        NSArray *kv = [pair componentsSeparatedByString:@"="];
        NSString *val =
            [[kv objectAtIndex:1]
             stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

        [params setObject:val forKey:[kv objectAtIndex:0]];
    }
  return params;
}

- (BOOL)handleOpenURL:(NSURL *)url {
    NSString *expected = [NSString stringWithFormat:@"%@://%@/", [self appScheme], kDBDropboxAPIVersion];
    if (![[url absoluteString] hasPrefix:expected]) {
        return NO;
    }
    
    NSArray *components = [[url path] pathComponents];
    NSString *methodName = [components count] > 1 ? [components objectAtIndex:1] : nil;
    
    if ([methodName isEqual:@"connect"]) {
        NSDictionary *params = [self parseURLParams:[url query]];
        NSString *token = [params objectForKey:@"oauth_token"];
        NSString *secret = [params objectForKey:@"oauth_token_secret"];
        NSString *userId = [params objectForKey:@"uid"];
        [self updateAccessToken:token accessTokenSecret:secret forUserId:userId];
    } else if ([methodName isEqual:@"cancelled"]) {
        DBLogInfo(@"DropboxSDK: user canceled Dropbox link");
    }
    
    return YES;
}

- (void)unlinkAll {
    [credentialStores removeAllObjects];
    [self clearSavedCredentials];
}

- (void)unlinkUserId:(NSString *)userId {
    [credentialStores removeObjectForKey:userId];
    [self saveCredentials];
}

- (MPOAuthCredentialConcreteStore *)credentialStoreForUserId:(NSString *)userId {
    if (!userId) {
        return [[[MPOAuthCredentialConcreteStore alloc] initWithCredentials:baseCredentials] autorelease];
    }
    return [credentialStores objectForKey:userId];
}

- (NSArray *)userIds {
    return [credentialStores allKeys];
}


#pragma mark private methods

- (NSDictionary *)savedCredentials {
    return [[NSUserDefaults standardUserDefaults] objectForKey:kDBDropboxSavedCredentials];
}

- (void)saveCredentials {
    NSMutableDictionary *credentials = [NSMutableDictionary dictionaryWithDictionary:baseCredentials];
    NSMutableArray *allUserCredentials = [NSMutableArray array];
    for (NSString *userId in [credentialStores allKeys]) {
        MPOAuthCredentialConcreteStore *store = [credentialStores objectForKey:userId];
        NSMutableDictionary *userCredentials = [NSMutableDictionary new];
        [userCredentials setObject:userId forKey:kDBDropboxUserId];
        [userCredentials setObject:store.accessToken forKey:kMPOAuthCredentialAccessToken];
        [userCredentials setObject:store.accessTokenSecret forKey:kMPOAuthCredentialAccessTokenSecret];
        [allUserCredentials addObject:userCredentials];
        [userCredentials release];
    }
    [credentials setObject:allUserCredentials forKey:kDBDropboxUserCredentials];
    
    [[NSUserDefaults standardUserDefaults] setObject:credentials forKey:kDBDropboxSavedCredentials];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDBDropboxSavedCredentialsOld];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)clearSavedCredentials {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kDBDropboxSavedCredentials];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSString *)appScheme {
    NSString *consumerKey = [baseCredentials objectForKey:kMPOAuthCredentialConsumerKey];
    return [NSString stringWithFormat:@"db-%@", consumerKey];
}

- (BOOL)appConformsToScheme {
    NSString *appScheme = [self appScheme];

    NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"Info" ofType:@"plist"];
    NSData *plistData = [NSData dataWithContentsOfFile:plistPath];
    NSDictionary *loadedPlist = 
            [NSPropertyListSerialization 
             propertyListFromData:plistData mutabilityOption:0 format:NULL errorDescription:NULL];

    NSArray *urlTypes = [loadedPlist objectForKey:@"CFBundleURLTypes"];
    for (NSDictionary *urlType in urlTypes) {
        NSArray *schemes = [urlType objectForKey:@"CFBundleURLSchemes"];
        for (NSString *scheme in schemes) {
            if ([scheme isEqual:appScheme]) {
                return YES;
            }
        }
    }
    return NO;
}

@end
