//
//  MTLJSONAdapter.m
//  Mantle
//
//  Created by Justin Spahr-Summers on 2013-02-12.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import "MTLJSONAdapter.h"
#import "MTLModel.h"
#import "MTLReflection.h"

NSString * const MTLJSONAdapterErrorDomain = @"MTLJSONAdapterErrorDomain";
const NSInteger MTLJSONAdapterErrorNoClassFound = 2;
const NSInteger MTLJSONAdapterErrorInvalidJSONDictionary = 3;
const NSInteger MTLJSONAdapterErrorInvalidJSONMapping = 4;

// An exception was thrown and caught.
const NSInteger MTLJSONAdapterErrorExceptionThrown = 1;

// Associated with the NSException that was caught.
static NSString * const MTLJSONAdapterThrownExceptionErrorKey = @"MTLJSONAdapterThrownException";

@interface MTLJSONAdapter ()

// The MTLModel subclass being parsed, or the class of `model` if parsing has
// completed.
@property (nonatomic, strong, readonly) Class modelClass;

// A cached copy of the return value of +JSONKeyPathsByPropertyKey.
@property (nonatomic, copy, readonly) NSDictionary *JSONKeyPathsByPropertyKey;

// Looks up the NSValueTransformer that should be used for the given key.
//
// key - The property key to transform from or to. This argument must not be nil.
//
// Returns a transformer to use, or nil to not transform the property.
- (NSValueTransformer *)JSONTransformerForKey:(NSString *)key;

@end

@interface NSString (Inflections)
- (NSString *)underscore;
- (NSString *)camelcase;
@end

@implementation NSString (Inflections)

static NSArray * TTTComponentsBySplittingOnWhitespaceWithString(NSString *string) {
//    string = [string stringByTrimmingCharactersInSet:[NSCharacterSet uppercaseLetterCharacterSet]];
    
    NSArray *components = [string componentsSeparatedByCharactersInSet:[NSCharacterSet uppercaseLetterCharacterSet]];
    components = [components filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self <> ''"]];
    
    return components;
}

NSString *splitOnCapital(NSString *s) {
    NSRange upcaseRange = NSMakeRange('A', 26);
    NSRange numberRange = NSMakeRange('0', 10);
    NSIndexSet *upcaseSet = [NSIndexSet indexSetWithIndexesInRange:upcaseRange];
    NSIndexSet *numberSet = [NSIndexSet indexSetWithIndexesInRange:numberRange];
    NSMutableString *result = [NSMutableString string];
    NSMutableString *oneWord = [NSMutableString string];
    BOOL prevLetterIsUc = NO;
    for (int i = 0; i < s.length; i++) {
        char oneChar = [s characterAtIndex:i];
        if ([upcaseSet containsIndex:oneChar]||[numberSet containsIndex:oneChar]) {
            if ( prevLetterIsUc ) {
            } else {
                if (result.length == 0) {
                    [result appendFormat:@"%@", [oneWord lowercaseString]];
                }else {
                    [result appendFormat:@"_%@", [oneWord lowercaseString]];
                }
                oneWord = [NSMutableString string];
            }
            prevLetterIsUc = YES;
        } else {
            prevLetterIsUc = NO;
        }
        [oneWord appendFormat:@"%c", oneChar];
    }
    if (oneWord.length > 0) {
        [result appendFormat:@"_%@", [oneWord lowercaseString]];
    }
    
    NSRange firstChar = [result rangeOfString:@"_"];
    if (firstChar.location == 0 ){
        result = [[result stringByReplacingCharactersInRange:firstChar withString:@""] mutableCopy];
    }
    return result;
}

- (NSString *)underscore
{

    NSString *str = splitOnCapital(self);
    return str;
//    NSScanner *scanner = [NSScanner scannerWithString:self];
//    scanner.caseSensitive = YES;
//    
//    NSCharacterSet *uppercase = [NSCharacterSet uppercaseLetterCharacterSet];
//    NSCharacterSet *lowercase = [NSCharacterSet lowercaseLetterCharacterSet];
//    
//    NSString *buffer = nil;
//    NSMutableString *output = [NSMutableString string];
//    
//    while (scanner.isAtEnd == NO) {
//        
//        if ([scanner scanCharactersFromSet:uppercase intoString:&buffer]) {
//            [output appendString:[buffer lowercaseString]];
//        }
//        
//        if ([scanner scanCharactersFromSet:lowercase intoString:&buffer]) {
//            [output appendString:buffer];
//            if (!scanner.isAtEnd)
//                [output appendString:@"_"];
//        }
//    }
//    
//    return [NSString stringWithString:output];
}

- (NSString *)camelcase
{
    NSArray *components = [self componentsSeparatedByString:@"_"];
    NSMutableString *output = [NSMutableString string];
    
    for (NSUInteger i = 0; i < components.count; i++) {
        if (i == 0) {
            [output appendString:components[i]];
        } else {
            [output appendString:[components[i] capitalizedString]];
        }
    }
    
    return [NSString stringWithString:output];
}

- (NSString *)classify
{
    return [[self camelcase] capitalizedString];
}

@end

@implementation MTLJSONAdapter

#pragma mark Convenience methods

+ (id)modelOfClass:(Class)modelClass fromJSONDictionary:(NSDictionary *)JSONDictionary error:(NSError **)error {
	MTLJSONAdapter *adapter = [[self alloc] initWithJSONDictionary:JSONDictionary modelClass:modelClass error:error];
	return adapter.model;
}

+ (NSArray *)modelsOfClass:(Class)modelClass fromJSONArray:(NSArray *)JSONArray error:(NSError **)error {
	if (JSONArray == nil || ![JSONArray isKindOfClass:NSArray.class]) {
		if (error != NULL) {
			NSDictionary *userInfo = @{
				NSLocalizedDescriptionKey: NSLocalizedString(@"Missing JSON array", @""),
				NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"%@ could not be created because an invalid JSON array was provided: %@", @""), NSStringFromClass(modelClass), JSONArray.class],
			};
			*error = [NSError errorWithDomain:MTLJSONAdapterErrorDomain code:MTLJSONAdapterErrorInvalidJSONDictionary userInfo:userInfo];
		}
		return nil;
	}

	NSMutableArray *models = [NSMutableArray arrayWithCapacity:JSONArray.count];
	for (NSDictionary *JSONDictionary in JSONArray){
		MTLModel *model = [self modelOfClass:modelClass fromJSONDictionary:JSONDictionary error:error];

		if (model == nil) return nil;
		
		[models addObject:model];
	}
	
	return models;
}

+ (NSDictionary *)JSONDictionaryFromModel:(MTLModel<MTLJSONSerializing> *)model {
	MTLJSONAdapter *adapter = [[self alloc] initWithModel:model];
	return adapter.JSONDictionary;
}

+ (NSArray *)JSONArrayFromModels:(NSArray *)models {
	NSParameterAssert(models != nil);
	NSParameterAssert([models isKindOfClass:NSArray.class]);

	NSMutableArray *JSONArray = [NSMutableArray arrayWithCapacity:models.count];
	for (MTLModel<MTLJSONSerializing> *model in models) {
		NSDictionary *JSONDictionary = [self JSONDictionaryFromModel:model];
		if (JSONDictionary == nil) return nil;

		[JSONArray addObject:JSONDictionary];
	}

	return JSONArray;
}

#pragma mark Lifecycle

- (id)init {
	NSAssert(NO, @"%@ must be initialized with a JSON dictionary or model object", self.class);
	return nil;
}

- (id)initWithJSONDictionary:(NSDictionary *)JSONDictionary modelClass:(Class)modelClass error:(NSError **)error {
	NSParameterAssert(modelClass != nil);
	NSParameterAssert([modelClass isSubclassOfClass:MTLModel.class]);
	NSParameterAssert([modelClass conformsToProtocol:@protocol(MTLJSONSerializing)]);

	if (JSONDictionary == nil || ![JSONDictionary isKindOfClass:NSDictionary.class]) {
		if (error != NULL) {
			NSDictionary *userInfo = @{
				NSLocalizedDescriptionKey: NSLocalizedString(@"Missing JSON dictionary", @""),
				NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"%@ could not be created because an invalid JSON dictionary was provided: %@", @""), NSStringFromClass(modelClass), JSONDictionary.class],
			};
			*error = [NSError errorWithDomain:MTLJSONAdapterErrorDomain code:MTLJSONAdapterErrorInvalidJSONDictionary userInfo:userInfo];
		}
		return nil;
	}

	if ([modelClass respondsToSelector:@selector(classForParsingJSONDictionary:)]) {
		modelClass = [modelClass classForParsingJSONDictionary:JSONDictionary];
		if (modelClass == nil) {
			if (error != NULL) {
				NSDictionary *userInfo = @{
					NSLocalizedDescriptionKey: NSLocalizedString(@"Could not parse JSON", @""),
					NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"No model class could be found to parse the JSON dictionary.", @"")
				};

				*error = [NSError errorWithDomain:MTLJSONAdapterErrorDomain code:MTLJSONAdapterErrorNoClassFound userInfo:userInfo];
			}

			return nil;
		}

		NSAssert([modelClass isSubclassOfClass:MTLModel.class], @"Class %@ returned from +classForParsingJSONDictionary: is not a subclass of MTLModel", modelClass);
		NSAssert([modelClass conformsToProtocol:@protocol(MTLJSONSerializing)], @"Class %@ returned from +classForParsingJSONDictionary: does not conform to <MTLJSONSerializing>", modelClass);
	}

	self = [super init];
	if (self == nil) return nil;

	_modelClass = modelClass;

	NSMutableDictionary *dictionaryValue = [[NSMutableDictionary alloc] initWithCapacity:JSONDictionary.count];

	NSMutableSet *propertyKeys = [[self.modelClass propertyKeys] mutableCopy];

    NSMutableDictionary *tempJSONKeyPaths = [[modelClass JSONKeyPathsByPropertyKey] mutableCopy];
    
    for (NSString *key in [self.modelClass propertyKeys]){
        id value = tempJSONKeyPaths[key];
        if (value == nil){
            NSString *snake = [key underscore];
            [tempJSONKeyPaths setObject:snake forKey:key];            
        }else{
        }
    }
    
    _JSONKeyPathsByPropertyKey = [tempJSONKeyPaths copy];
    
	for (NSString *mappedPropertyKey in self.JSONKeyPathsByPropertyKey) {
		if (![propertyKeys containsObject:mappedPropertyKey]) {
			NSAssert(NO, @"%@ is not a property of %@.", mappedPropertyKey, modelClass);
			return nil;
		}

		id value = self.JSONKeyPathsByPropertyKey[mappedPropertyKey];

		if (![value isKindOfClass:NSString.class] && value != NSNull.null) {
			NSAssert(NO, @"%@ must either map to a JSON key path or NSNull, got: %@.",mappedPropertyKey, value);
			return nil;
		}
	}

	for (NSString *propertyKey in propertyKeys) {
		NSString *JSONKeyPath = [self JSONKeyPathForPropertyKey:propertyKey];
		if (JSONKeyPath == nil) continue;

		id value;
		@try {
            value = [JSONDictionary valueForKeyPath:JSONKeyPath];
		} @catch (NSException *ex) {
			if (error != NULL) {
				NSDictionary *userInfo = @{
					NSLocalizedDescriptionKey: NSLocalizedString(@"Invalid JSON dictionary", nil),
					NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:NSLocalizedString(@"%1$@ could not be parsed because an invalid JSON dictionary was provided for key path \"%2$@\"", nil), modelClass, JSONKeyPath],
					MTLJSONAdapterThrownExceptionErrorKey: ex
				};

				*error = [NSError errorWithDomain:MTLJSONAdapterErrorDomain code:MTLJSONAdapterErrorInvalidJSONDictionary userInfo:userInfo];
			}

			return nil;
		}

		if (value == nil) continue;

		@try {
			NSValueTransformer *transformer = [self JSONTransformerForKey:propertyKey];
			if (transformer != nil) {
				// Map NSNull -> nil for the transformer, and then back for the
				// dictionary we're going to insert into.
				if ([value isEqual:NSNull.null]) value = nil;
				value = [transformer transformedValue:value] ?: NSNull.null;
			}

			dictionaryValue[propertyKey] = value;
		} @catch (NSException *ex) {
			NSLog(@"*** Caught exception %@ parsing JSON key path \"%@\" from: %@", ex, JSONKeyPath, JSONDictionary);

			// Fail fast in Debug builds.
			#if DEBUG
			@throw ex;
			#else
			if (error != NULL) {
				NSDictionary *userInfo = @{
					NSLocalizedDescriptionKey: ex.description,
					NSLocalizedFailureReasonErrorKey: ex.reason,
					MTLJSONAdapterThrownExceptionErrorKey: ex
				};

				*error = [NSError errorWithDomain:MTLJSONAdapterErrorDomain code:MTLJSONAdapterErrorExceptionThrown userInfo:userInfo];
			}

			return nil;
			#endif
		}
	}

	_model = [self.modelClass modelWithDictionary:dictionaryValue error:error];
	if (_model == nil) return nil;

	return self;
}

- (id)initWithModel:(MTLModel<MTLJSONSerializing> *)model {
	NSParameterAssert(model != nil);

	self = [super init];
	if (self == nil) return nil;

	_model = model;
	_modelClass = model.class;
    _JSONKeyPathsByPropertyKey = [[model.class JSONKeyPathsByPropertyKey] copy];

    NSMutableSet *propertyKeys = [[_modelClass propertyKeys] mutableCopy];
    
    NSMutableDictionary *tempJSONKeyPaths = [[_modelClass JSONKeyPathsByPropertyKey] mutableCopy];
    
    for (NSString *key in [_modelClass propertyKeys]){
        id value = tempJSONKeyPaths[key];
        if (value == nil){
            NSString *snake = [key underscore];
            [tempJSONKeyPaths setObject:snake forKey:key];
        }else{
        }
    }
    
    _JSONKeyPathsByPropertyKey = [tempJSONKeyPaths copy];

    return self;
}

#pragma mark Serialization

- (NSDictionary *)JSONDictionary {
	NSDictionary *dictionaryValue = self.model.dictionaryValue;
	NSMutableDictionary *JSONDictionary = [[NSMutableDictionary alloc] initWithCapacity:dictionaryValue.count];

	[dictionaryValue enumerateKeysAndObjectsUsingBlock:^(NSString *propertyKey, id value, BOOL *stop) {
		NSString *JSONKeyPath = [self JSONKeyPathForPropertyKey:propertyKey];
		if (JSONKeyPath == nil) return;

		NSValueTransformer *transformer = [self JSONTransformerForKey:propertyKey];
		if ([transformer.class allowsReverseTransformation]) {
			// Map NSNull -> nil for the transformer, and then back for the
			// dictionaryValue we're going to insert into.
			if ([value isEqual:NSNull.null]) value = nil;
			value = [transformer reverseTransformedValue:value] ?: NSNull.null;
		}

		NSArray *keyPathComponents = [JSONKeyPath componentsSeparatedByString:@"."];

		// Set up dictionaries at each step of the key path.
		id obj = JSONDictionary;
		for (NSString *component in keyPathComponents) {
			if ([obj valueForKey:component] == nil) {
				// Insert an empty mutable dictionary at this spot so that we
				// can set the whole key path afterward.
				[obj setValue:[NSMutableDictionary dictionary] forKey:component];
			}

			obj = [obj valueForKey:component];
		}

		[JSONDictionary setValue:value forKeyPath:JSONKeyPath];
	}];

	return JSONDictionary;
}

- (NSValueTransformer *)JSONTransformerForKey:(NSString *)key {
	NSParameterAssert(key != nil);

	SEL selector = MTLSelectorWithKeyPattern(key, "JSONTransformer");
	if ([self.modelClass respondsToSelector:selector]) {
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self.modelClass methodSignatureForSelector:selector]];
		invocation.target = self.modelClass;
		invocation.selector = selector;
		[invocation invoke];

		__unsafe_unretained id result = nil;
		[invocation getReturnValue:&result];
		return result;
	}

	if ([self.modelClass respondsToSelector:@selector(JSONTransformerForKey:)]) {
		return [self.modelClass JSONTransformerForKey:key];
	}

	return nil;
}

- (NSString *)JSONKeyPathForPropertyKey:(NSString *)key {
	NSParameterAssert(key != nil);

	id JSONKeyPath = self.JSONKeyPathsByPropertyKey[key];
	if ([JSONKeyPath isEqual:NSNull.null]) return nil;

	if (JSONKeyPath == nil) {
		return key;
	} else {
		return JSONKeyPath;
	}
}

@end

@implementation MTLJSONAdapter (Deprecated)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

+ (id)modelOfClass:(Class)modelClass fromJSONDictionary:(NSDictionary *)JSONDictionary {
	return [self modelOfClass:modelClass fromJSONDictionary:JSONDictionary error:NULL];
}

- (id)initWithJSONDictionary:(NSDictionary *)JSONDictionary modelClass:(Class)modelClass {
	return [self initWithJSONDictionary:JSONDictionary modelClass:modelClass error:NULL];
}

#pragma clang diagnostic pop

@end
