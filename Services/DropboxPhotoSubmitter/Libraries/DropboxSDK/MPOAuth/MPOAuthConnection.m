//
//  MPOAuthConnection.m
//  MPOAuthConnection
//
//  Created by Karl Adam on 08.12.05.
//  Copyright 2008 matrixPointer. All rights reserved.
//

#if __has_feature(objc_arc)
#error This file must be compiled with Non-ARC. use -fno-objc_arc flag (or convert project to Non-ARC)
#endif

#import "MPOAuthConnection.h"
#import "MPOAuthURLRequest.h"
#import "MPOAuthURLResponse.h"
#import "MPOAuthParameterFactory.h"
#import "MPOAuthCredentialConcreteStore.h"

@interface MPOAuthURLResponse ()
@property (nonatomic, readwrite, retain) NSURLResponse *urlResponse;
@property (nonatomic, readwrite, retain) NSDictionary *oauthParameters;
@end

@implementation MPOAuthConnection

+ (MPOAuthConnection *)connectionWithRequest:(MPOAuthURLRequest *)inRequest delegate:(id)inDelegate credentials:(NSObject <MPOAuthCredentialStore, MPOAuthParameterFactory> *)inCredentials {
	MPOAuthConnection *aConnection = [[MPOAuthConnection alloc] initWithRequest:inRequest delegate:inDelegate credentials:inCredentials];
	return [aConnection autorelease];
}

+ (NSData *)sendSynchronousRequest:(MPOAuthURLRequest *)inRequest usingCredentials:(NSObject <MPOAuthCredentialStore, MPOAuthParameterFactory> *)inCredentials returningResponse:(MPOAuthURLResponse **)outResponse error:(NSError **)inError {
	[inRequest addParameters:[inCredentials oauthParameters]];
	NSURLRequest *urlRequest = [inRequest urlRequestSignedWithSecret:[inCredentials signingKey] usingMethod:[inCredentials signatureMethod]];
	NSURLResponse *urlResponse = nil;
	NSData *responseData = [self sendSynchronousRequest:urlRequest returningResponse:&urlResponse error:inError];
	MPOAuthURLResponse *oauthResponse = [[[MPOAuthURLResponse alloc] init] autorelease];
	oauthResponse.urlResponse = urlResponse;
	*outResponse = oauthResponse;
	
	return responseData;
}

- (id)initWithRequest:(MPOAuthURLRequest *)inRequest delegate:(id)inDelegate credentials:(NSObject <MPOAuthCredentialStore, MPOAuthParameterFactory> *)inCredentials {
	[inRequest addParameters:[inCredentials oauthParameters]];
	NSURLRequest *urlRequest = [inRequest urlRequestSignedWithSecret:[inCredentials signingKey] usingMethod:[inCredentials signatureMethod]];
	if ((self = [super initWithRequest:urlRequest delegate:inDelegate])) {
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincompatible-pointer-types"
		_credentials = [inCredentials retain];
#pragma clang diagnostic pop
	}
	return self;
}

- (oneway void)dealloc {
	[_credentials release];
	
	[super dealloc];
}

@synthesize credentials = _credentials;

#pragma mark -

@end
