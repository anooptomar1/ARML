//
//  ViewController.m
//  MLAR
//
//  Created by moxin on 2017/10/3.
//  Copyright © 2017年 Vizlab. All rights reserved.
//

#import "ViewController.h"
#import <SceneKit/SceneKit.h>
#import <SceneKit/SCNCamera.h>
#import <ARKit/ARKit.h>
#import <Vision/Vision.h>
#import <AVFoundation/AVFoundation.h>
#import "VisionDetector.h"
#import "ARTextNode.h"
#import "Utils.h"

@interface ViewController () <ARSCNViewDelegate,ARSessionDelegate>{}

@property (nonatomic, strong)ARSCNView *sceneView;


@end

@implementation ViewController{
    VisionDetector* _faceDetector;
}


- (void)viewDidLoad {
    [super viewDidLoad];
    
    //setup sceneView
    self.sceneView = [[ARSCNView alloc]initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.frame), CGRectGetHeight(self.view.frame))];
    self.sceneView.delegate = self;
    self.sceneView.showsStatistics = YES;
    self.sceneView.autoenablesDefaultLighting = YES;
    [self.view addSubview:self.sceneView];
    
    //config session
    ARWorldTrackingConfiguration* configuration = [ARWorldTrackingConfiguration new];
    configuration.planeDetection = ARPlaneDetectionHorizontal;
    self.sceneView.session.delegate = self;
    [self.sceneView.session runWithConfiguration:configuration];
    
    //let the camera initialize
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        _faceDetector = [[VisionDetector alloc]initWithARSession:self.sceneView.session];
       
        __weak ViewController* weakSelf = self;
        [_faceDetector detectingFaceswithCompletion:^(CGRect normalizedRect, NSString* name) {
            //fresh UI
            [weakSelf display:normalizedRect withName:name];
        }];
    });
    
    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

}


- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [self.sceneView.session pause];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}



#pragma mark - ARSessionDelegate

- (void)session:(ARSession *)session cameraDidChangeTrackingState:(ARCamera *)camera{
    
    switch (camera.trackingStateReason) {
        case ARTrackingStateReasonInitializing:
        {
            //hack camera to make it auto focus
            NSArray* availableSensors =  [self.sceneView.session valueForKey:@"availableSensors"];
            for(id sensor in availableSensors){
                if ([sensor isKindOfClass:NSClassFromString(@"ARImageSensor")]) {
                    id imageSensor = sensor;
                    AVCaptureSession* captureSession = [imageSensor valueForKey:@"captureSession"];
                    AVCaptureDevice* captureDevice = [imageSensor valueForKey:@"captureDevice"];
                    
                    if(captureSession && captureDevice)
                    {
                        if([captureDevice lockForConfiguration:nil]){
                            [captureSession beginConfiguration];
                            captureDevice.focusMode = AVCaptureFocusModeContinuousAutoFocus;
                            captureDevice.smoothAutoFocusEnabled = YES;
                            [captureDevice unlockForConfiguration];
                        }
                    }
                }
            }
            break;
        }
            
        default:
            break;
    }
    
}


#pragma mark - private methods

const NSInteger kFaceRectangle = 10;
- (void)display:(CGRect)normalizedRect withName:(NSString* )name{
    
    [self.sceneView.scene.rootNode.childNodes makeObjectsPerformSelector:@selector(removeFromParentNode)];
    [[self.view viewWithTag:kFaceRectangle] removeFromSuperview];
    if (!CGRectEqualToRect(normalizedRect, CGRectZero)) {
        
        //add rectangle
        CGRect faceRect = transformNormalizedBoundingRect(self.view.bounds.size, normalizedRect);
        UIView* view = [[UIView alloc]initWithFrame:faceRect];
        view.tag = kFaceRectangle;
        view.alpha = 0.2;
        view.backgroundColor = [UIColor redColor];
        UILabel* nameLabel = [[UILabel alloc]initWithFrame:CGRectMake(0, (faceRect.size.height-20)/2, faceRect.size.width, 30)];
        nameLabel.textColor = [UIColor yellowColor];
        nameLabel.textAlignment = NSTextAlignmentCenter;
        nameLabel.font = [UIFont systemFontOfSize:20.0f];
        nameLabel.text = name;
        [view addSubview:nameLabel];
        [self.view addSubview:view];
        
        if(![name isEqualToString:@"unknown"]){
            
            CGPoint faceRectCenter = (CGPoint){CGRectGetMidX(faceRect),CGRectGetMidY(faceRect)};
            __block NSMutableArray<ARHitTestResult* >* testResults = [NSMutableArray new];
            
            void(^hitTest)(void) = ^{
              
                NSArray<ARHitTestResult* >* hitTestResults = [self.sceneView hitTest:faceRectCenter types:ARHitTestResultTypeFeaturePoint];
                if(hitTestResults.count > 0){
                    //get the first
                    ARHitTestResult* firstResult = nil;
                    for (ARHitTestResult* result in hitTestResults) {
                        if (result.distance > 0.10) {
                            firstResult = result;
                            [testResults addObject:firstResult];
                            break;
                        }
                    }
                }
            };
            
            //3次求平均值，防止漂移
            for(int i=0; i<3; i++){
                hitTest();
//                usleep(12000r);
            }
            
            if(testResults.count > 0){
                
                SCNVector3 postion = averagePostion([testResults copy]);
                 NSLog(@"<%.1f,%.1f,%.1f>",postion.x,postion.y,postion.z);
                __block SCNNode* textNode = [ARTextNode nodeWithText:name Position:postion];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.sceneView.scene.rootNode addChildNode:textNode];
                    [textNode show];
                });
            }
            else{
                NSLog(@"HitTest invalid");
            }
        }
    }
}




@end
