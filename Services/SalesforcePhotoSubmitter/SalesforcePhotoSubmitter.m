//
//  SalesforcePhotoSubmitter.m
//  tottepost
//
//  Created by Kentaro ISHITOYA on 12/04/08.
//  Copyright (c) 2012 cocotomo. All rights reserved.
//

#if ! __has_feature(objc_arc)
#error This file must be compiled with ARC. Use -fobjc-arc flag (or convert project to ARC).
#endif

#import "SalesforceAPIKey.h"
#import "SalesforcePhotoSubmitter.h"
#import "PhotoSubmitterManager.h"
#import "RegexKitLite.h"
#import "RestKit.h"
#import "SFMappingManager.h"
#import "SFUser.h"
#import "SFAuthContext.h"
#import "SFOAuthViewController.h"
#import "SFConfig.h"

//-----------------------------------------------------------------------------
//Private Implementations
//-----------------------------------------------------------------------------
@interface SalesforcePhotoSubmitter(PrivateImplementation)
- (void) setupInitialState;
- (void) clearCredentials;
- (void) initRestKitAndUser;
- (NSString*)addTextParam:(NSString*)param value:(NSString*)value body:(NSString*)body boundary:(NSString*)boundary;
- (id)onSubmitContent:(PhotoSubmitterContentEntity *)content andOperationDelegate:(id<PhotoSubmitterPhotoOperationDelegate>)delegate;
@end

@implementation SalesforcePhotoSubmitter(PrivateImplementation)
#pragma mark - private implementations
/*!
 * initializer
 */
-(void)setupInitialState{
    [self setSubmitterIsConcurrent:NO 
                      isSequencial:NO 
                     usesOperation:YES 
                   requiresNetwork:YES 
                  isAlbumSupported:YES];
}

/*!
 * clear Salesforce credential
 */
- (void)clearCredentials{
	[[SFAuthContext context] clear];
}

/*!
 * initialize restkit
 */
- (void)initRestKitAndUser {
	[SFMappingManager initialize];
    self.username = [SFAuthContext context].identity.display_name;
}

/*!
 * add text param to request
 */
- (NSString*)addTextParam:(NSString*)param value:(NSString*)value body:(NSString*)body boundary:(NSString*)boundary {
	NSString* start = [NSString stringWithFormat:@"%@Content-Disposition: form-data; name=\"%@\"\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n", body, param];
	return [NSString stringWithFormat:@"%@%@%@", start, value, boundary];
}

/*!
 * submit content
 */
- (id)onSubmitContent:(PhotoSubmitterContentEntity *)content andOperationDelegate:(id<PhotoSubmitterPhotoOperationDelegate>)delegate{
    
    NSString *url = [SFConfig addVersionPrefix:@"/chatter/feeds/news/me/feed-items"];
	NSString* targetUrl = [NSString stringWithFormat:@"%@%@", [[SFAuthContext context] instanceUrl], url];
	NSMutableURLRequest* request = 
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:targetUrl]
                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData 
                            timeoutInterval:60];
	
	[[SFAuthContext context] addOAuthHeaderToNSRequest:request];
	[request setHTTPMethod:@"POST"];
	
	NSString* boundary = @"-----------------2342342352342343";
	
	[request addValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
   forHTTPHeaderField:@"Content-Type"];
	
	// Assemble the body.
	NSString* boundaryBreak = [NSString stringWithFormat:@"\r\n--%@\r\n", boundary];
	NSString* body = boundaryBreak;
    
    if(content.comment != nil){
        body = [self addTextParam:@"text" value:content.comment body:body boundary:boundaryBreak];
    }
	
	NSDateFormatter* dateFormat = [[NSDateFormatter alloc] init];
	[dateFormat setDateFormat:@"M/d/y h:m:s"];
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat  = @"yyyyMMddHHmmssSSSS";
    NSString *filename = nil;
    if(content.isPhoto){
        filename = [NSString stringWithFormat:@"%@.jpg", [df stringFromDate:content.timestamp]];
    }else{
        filename = [NSString stringWithFormat:@"%@.mp4", [df stringFromDate:content.timestamp]];
    }
	
	body = [self addTextParam:@"fileName" value:filename body:body boundary:boundaryBreak];
	
	body = [NSString stringWithFormat:@"%@Content-Disposition: form-data; name=\"feedItemFileUpload\"; filename=\"%@\"\r\n", body, filename];
	body = [NSString stringWithFormat:@"%@Content-Type: application/octet-stream\r\n\r\n", body];
	
	NSMutableData* bodyData = [NSMutableData data];
	[bodyData appendData:[body dataUsingEncoding:NSUTF8StringEncoding]];
	[bodyData appendData:content.data];
	
	NSData* boundaryDataEnd = [[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding];
	[bodyData appendData:boundaryDataEnd];
	
	[request setHTTPBody:bodyData];
	
    NSURLConnection *connection = [NSURLConnection connectionWithRequest:request delegate:self];
    return connection;
    
    /*
    // implementation with RKParams, currently this code does not work.
    RKParams *params = [RKParams params];
    if(content.comment != nil){
        [params setValue:content.comment forParam:@"text"];
    }
    //RKParamsAttachment *attachment = [params setData:content.data forParam:@"feedItemFileUpload"];
    
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat  = @"yyyyMMddHHmmssSSSS";
    if(content.isPhoto){
        attachment.MIMEType = @"image/jpeg";
        attachment.fileName = [NSString stringWithFormat:@"%@.jpg", [df stringFromDate:content.timestamp]];
    }else{
        attachment.MIMEType = @"video/mp4";
        attachment.fileName = [NSString stringWithFormat:@"%@.mp4", [df stringFromDate:content.timestamp]];
    }    
    NSLog(@"RKParams HTTPHeaderValueForContentType = %@", [params HTTPHeaderValueForContentType]);
    NSLog(@"RKParams HTTPHeaderValueForContentLength = %d", [params HTTPHeaderValueForContentLength]);
    
    RKClient *client = [RKClient clientWithBaseURL:[SFAuthContext context].instanceUrl];
    client.defaultHTTPEncoding = NSUTF8StringEncoding;
    RKRequest *request = [client post:url params:params delegate:self];
    return request;
     */
}

#pragma mark - NSURLConnection delegates
/*!
 * did fail
 */
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    [self completeSubmitContentWithRequest:connection andError:error];
}

/*!
 * did finished
 */
-(void)connectionDidFinishLoading:(NSURLConnection *)connection{
    [self completeSubmitContentWithRequest:connection];    
}

/*!
 * progress
 */
- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite{
    CGFloat progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
    NSString *hash = [self photoForRequest:connection];
    [self photoSubmitter:self didProgressChanged:hash progress:progress];
}

//#pragma mark - RKClient delegates
///*!
// * did load response
// */
//- (void)request:(RKRequest *)request didLoadResponse:(RKResponse *)response{
//    NSLog(@"%@", request);
//    if(response.isSuccessful){
//        [self completeSubmitContentWithRequest:request];
//    }else{
//        [self completeSubmitContentWithRequest:request andError:nil];
//    }
//}
//
///*!
// * did send body data, progress
// */
//- (void)request:(RKRequest *)request didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite{
//    CGFloat progress = (float)totalBytesWritten / (float)totalBytesExpectedToWrite;
//    NSString *hash = [self photoForRequest:request];
//    [self photoSubmitter:self didProgressChanged:hash progress:progress];    
//}
//
///*! 
// * did fail
// */
//- (void)request:(RKRequest *)request didFailLoadWithError:(NSError *)error{
//    [self completeSubmitContentWithRequest:request andError:error];
//}
//
///*!
// * did timeout
// */
//- (void)requestDidTimeout:(RKRequest *)request{
//    [self completeSubmitContentWithRequest:request andError:nil];
//}
//
///*!
// * request will prepare for send
// */
//- (void)requestWillPrepareForSend:(RKRequest *)request{
//    request.defaultHTTPEncoding = NSUTF8StringEncoding;
//    [[SFAuthContext context] addOAuthHeader:request];
//}
@end

//-----------------------------------------------------------------------------
//Public Implementations
//-----------------------------------------------------------------------------
#pragma mark - public PhotoSubmitter Protocol implementations
@implementation SalesforcePhotoSubmitter
@synthesize authDelegate;
@synthesize dataDelegate;
@synthesize albumDelegate;
/*!
 * initialize
 */
- (id)init{
    self = [super init];
    if (self) {
        [self setupInitialState];
    }
    return self;
}

#pragma mark - authorization
/*!
 * login to Salesforce
 */
-(void)onLogin{
	[SFMappingManager initialize];
	SFOAuthViewController* oauthViewController = [[SFOAuthViewController alloc] init]; 
	[[[PhotoSubmitterManager sharedInstance].authControllerDelegate requestNavigationControllerToPresentAuthenticationView] pushViewController:oauthViewController animated:YES];
    [SFAuthContext context].delegate = self;
}

/*!
 * logoff from Salesforce
 */
- (void)onLogout{
    [self clearCredentials];
    [self completeLogout];
}

/*!
 * refresh credential
 */
- (void)refreshCredential{
    if([self isSessionValid] == NO){
        [SFMappingManager initialize];
        [[SFAuthContext context] load];
        [[SFAuthContext context] startGettingAccessTokenWithDelegate:self];
    }
}

/*!
 * check is session valid
 */
- (BOOL)isSessionValid{
    return [[SFAuthContext context] accessToken] != nil;
}

#pragma mark - photo
/*!
 * submit photo with data, comment and delegate
 */
- (id)onSubmitPhoto:(PhotoSubmitterImageEntity *)photo andOperationDelegate:(id<PhotoSubmitterPhotoOperationDelegate>)delegate{
    return [self onSubmitContent:photo andOperationDelegate:delegate];
}

/*!
 * submit video
 */
- (id)onSubmitVideo:(PhotoSubmitterVideoEntity *)video andOperationDelegate:(id<PhotoSubmitterPhotoOperationDelegate>)delegate{
    return [self onSubmitContent:video andOperationDelegate:delegate];
}

/*!
 * cancel content upload
 */
- (id)onCancelContentSubmit:(PhotoSubmitterContentEntity *)content{
    RKRequest *request = (RKRequest *)[self requestForPhoto:content.contentHash];
    [request cancel];
    return request;
}

/*!
 * is video supported
 */
- (BOOL)isVideoSupported{
    return YES;
}

#pragma mark - album
/*!
 * is album supported
 */
- (BOOL)isAlbumSupported{
    return NO;
}


#pragma mark - AccessTokenRefreshDelegate
/*!
 * access token refresh completed
 */
- (void)refreshCompleted{
    [self completeLogin];
}

/*!
 * login completed
 */
- (void)loginCompleted{
    [self initRestKitAndUser];
    [self completeLogin];
}

/*!
 * login completed
 */
- (void)loginCompletedWithError:(NSError *)error{
    NSLog(@"%s, %@", __PRETTY_FUNCTION__, error.description);
    [self completeLoginFailed];
}

#pragma mark - SFOAuthViewControllerDelegate
/*!
 * auth view dismissed
 */
- (void)authViewControllerDismissed:(SFOAuthViewController *)controller{
    [self completeLoginFailed];
}
@end
