/* PassKit Objective-C compatibility surface for the Telegram package mirror.
 * Stripe's STPAPIClient/STPPaymentConfiguration compile against Apple Pay
 * types; Apple Pay never runs on QuillOS, so the surface is inert. */
#ifndef QUILL_OBJC_PASSKIT_H
#define QUILL_OBJC_PASSKIT_H

#include <Foundation/Foundation.h>

#if defined(__OBJC__)

typedef NS_OPTIONS(NSUInteger, PKMerchantCapability) {
    PKMerchantCapability3DS = 1UL << 0,
    PKMerchantCapabilityEMV = 1UL << 1,
    PKMerchantCapabilityCredit = 1UL << 2,
    PKMerchantCapabilityDebit = 1UL << 3,
};

typedef NSString *PKPaymentNetwork;
static PKPaymentNetwork const PKPaymentNetworkAmex = @"Amex";
static PKPaymentNetwork const PKPaymentNetworkDiscover = @"Discover";
static PKPaymentNetwork const PKPaymentNetworkMasterCard = @"MasterCard";
static PKPaymentNetwork const PKPaymentNetworkVisa = @"Visa";

@interface PKPaymentToken : NSObject
@property (nonatomic, readonly) NSData *paymentData;
@property (nonatomic, readonly) NSString *transactionIdentifier;
@end

@interface PKPayment : NSObject
@property (nonatomic, readonly) PKPaymentToken *token;
@end

@interface PKPaymentSummaryItem : NSObject
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSDecimalNumber *amount;
@end

@interface PKPaymentRequest : NSObject
@property (nonatomic, copy) NSString *merchantIdentifier;
@property (nonatomic, copy) NSString *countryCode;
@property (nonatomic, copy) NSString *currencyCode;
@property (nonatomic, copy) NSArray<PKPaymentNetwork> *supportedNetworks;
@property (nonatomic) PKMerchantCapability merchantCapabilities;
@property (nonatomic, copy) NSArray<PKPaymentSummaryItem *> *paymentSummaryItems;
@end

@interface PKPaymentAuthorizationViewController : NSObject
+ (BOOL)canMakePayments;
+ (BOOL)canMakePaymentsUsingNetworks:(NSArray<PKPaymentNetwork> *)supportedNetworks;
@end

#endif /* __OBJC__ */

#endif /* QUILL_OBJC_PASSKIT_H */
