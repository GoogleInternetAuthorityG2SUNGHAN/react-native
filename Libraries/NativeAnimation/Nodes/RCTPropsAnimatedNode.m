/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "RCTPropsAnimatedNode.h"

#import <objc/runtime.h>

#import <React/RCTLog.h>
#import <React/RCTUIManager.h>

#import "RCTAnimationUtils.h"
#import "RCTStyleAnimatedNode.h"
#import "RCTValueAnimatedNode.h"

// TODO: Eventually we should just include RCTSurfacePresenter.h, but that pulls in all of fabric
// which doesn't compile in open source yet, so we mirror the protocol and duplicate the category
// here for now.

@protocol SyncViewUpdater <NSObject>

- (BOOL)synchronouslyUpdateViewOnUIThread:(NSNumber *)reactTag props:(NSDictionary *)props;

@end

@implementation RCTBridge (SurfacePresenterShadow)

- (id<SyncViewUpdater>)surfacePresenter
{
  return objc_getAssociatedObject(self, @selector(surfacePresenter));
}

@end


@implementation RCTPropsAnimatedNode
{
  NSNumber *_connectedViewTag;
  NSNumber *_rootTag;
  NSString *_connectedViewName;
  __weak RCTBridge *_bridge;
  NSMutableDictionary<NSString *, NSObject *> *_propsDictionary; // TODO: use RawProps or folly::dynamic directly
}

- (instancetype)initWithTag:(NSNumber *)tag
                     config:(NSDictionary<NSString *, id> *)config;
{
  if (self = [super initWithTag:tag config:config]) {
    _propsDictionary = [NSMutableDictionary new];
  }
  return self;
}

- (void)connectToView:(NSNumber *)viewTag
             viewName:(NSString *)viewName
               bridge:(RCTBridge *)bridge
{
  _connectedViewTag = viewTag;
  _connectedViewName = viewName;
  _bridge = bridge;
  _rootTag = nil;
}

- (void)disconnectFromView:(NSNumber *)viewTag
{
  _connectedViewTag = nil;
  _connectedViewName = nil;
  _bridge = nil;
  _rootTag = nil;
}

- (void)updateView
{
  BOOL fabricUpdateSuccess = [_bridge.surfacePresenter synchronouslyUpdateViewOnUIThread:_connectedViewTag
                                                                                   props:_propsDictionary];
  if (fabricUpdateSuccess) {
    return;
  }
  [_bridge.uiManager synchronouslyUpdateViewOnUIThread:_connectedViewTag
                                              viewName:_connectedViewName
                                                 props:_propsDictionary];
}

- (void)restoreDefaultValues
{
  // Restore the default value for all props that were modified by this node.
  for (NSString *key in _propsDictionary.allKeys) {
    _propsDictionary[key] = [NSNull null];
  }

  if (_propsDictionary.count) {
    [self updateView];
  }
}

- (NSString *)propertyNameForParentTag:(NSNumber *)parentTag
{
  __block NSString *propertyName;
  [self.config[@"props"] enumerateKeysAndObjectsUsingBlock:^(NSString *_Nonnull property, NSNumber *_Nonnull tag, BOOL *_Nonnull stop) {
    if ([tag isEqualToNumber:parentTag]) {
      propertyName = property;
      *stop = YES;
    }
  }];
  return propertyName;
}

- (void)performUpdate
{
  [super performUpdate];

  // Since we are updating nodes after detaching them from views there is a time where it's
  // possible that the view was disconnected and still receive an update, this is normal and we can
  // simply skip that update.
  if (!_connectedViewTag) {
    return;
  }

  for (NSNumber *parentTag in self.parentNodes.keyEnumerator) {
    RCTAnimatedNode *parentNode = [self.parentNodes objectForKey:parentTag];
    if ([parentNode isKindOfClass:[RCTStyleAnimatedNode class]]) {
      [self->_propsDictionary addEntriesFromDictionary:[(RCTStyleAnimatedNode *)parentNode propsDictionary]];

    } else if ([parentNode isKindOfClass:[RCTValueAnimatedNode class]]) {
      NSString *property = [self propertyNameForParentTag:parentTag];
      CGFloat value = [(RCTValueAnimatedNode *)parentNode value];
      self->_propsDictionary[property] = @(value);
    }
  }

  if (_propsDictionary.count) {
    [self updateView];
  }
}

@end
