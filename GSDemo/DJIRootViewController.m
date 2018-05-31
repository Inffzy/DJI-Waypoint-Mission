//
//  DJIRootViewController.m
//  GSDemo
//
//  Created by DJI on 7/7/15.
//  Copyright (c) 2015 DJI. All rights reserved.
//

#import "DJIRootViewController.h"
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import <DJISDK/DJISDK.h>
#import "DJIMapController.h"
#import "DJIGSButtonViewController.h"
#import "DJIWaypointConfigViewController.h"
#import "DemoUtility.h"

#define ENTER_DEBUG_MODE 0
#define MAX_FLIGHT_SPEED 15
#define AUTO_FLIGHT_SPEED 12

@interface DJIRootViewController ()<DJIGSButtonViewControllerDelegate, DJIWaypointConfigViewControllerDelegate, MKMapViewDelegate, CLLocationManagerDelegate, DJISDKManagerDelegate, DJIFlightControllerDelegate>
{
    NSNumber *missionProgress;
    NSMutableArray *allCoordinates;
}

@property (nonatomic, assign) BOOL isEditingPoints;
@property (nonatomic, strong) DJIGSButtonViewController *gsButtonVC;
@property (nonatomic, strong) DJIWaypointConfigViewController *waypointConfigVC;
@property (nonatomic, strong) DJIMapController *mapController;

@property(nonatomic, strong) CLLocationManager* locationManager;
@property(nonatomic, assign) CLLocationCoordinate2D userLocation;
@property(nonatomic, assign) CLLocationCoordinate2D droneLocation;
@property(nonatomic, strong) UITapGestureRecognizer *tapGesture;
@property (strong, nonatomic) NSMutableArray *editPoints;

@property (weak, nonatomic) IBOutlet MKMapView *mapView;
@property (weak, nonatomic) IBOutlet UIView *topBarView;
@property(nonatomic, strong) IBOutlet UILabel *modeLabel;
@property(nonatomic, strong) IBOutlet UILabel *gpsLabel;
@property(nonatomic, strong) IBOutlet UILabel *hsLabel;
@property(nonatomic, strong) IBOutlet UILabel *vsLabel;
@property(nonatomic, strong) IBOutlet UILabel *altitudeLabel;

@property(nonatomic, strong) DJIMutableWaypointMission *waypointMission;
@end

@implementation DJIRootViewController

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [self startUpdateLocation];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.locationManager stopUpdatingLocation];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self registerApp];
    
    [self initUI];
    [self initData];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)prefersStatusBarHidden {
    return NO;
}

#pragma mark Init Methods
-(void)initData
{
    self.userLocation = kCLLocationCoordinate2DInvalid;
    self.droneLocation = kCLLocationCoordinate2DInvalid;
    
    self.mapController = [[DJIMapController alloc] init];
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(addWaypoints:)];
    [self.mapView addGestureRecognizer:self.tapGesture];
}

-(void) initUI
{
    self.modeLabel.text = @"N/A";
    self.gpsLabel.text = @"0";
    self.vsLabel.text = @"0.0 M/S";
    self.hsLabel.text = @"0.0 M/S";
    self.altitudeLabel.text = @"0 M";
    
    self.gsButtonVC = [[DJIGSButtonViewController alloc] initWithNibName:@"DJIGSButtonViewController" bundle:[NSBundle mainBundle]];
    [self.gsButtonVC.view setFrame:CGRectMake(0, self.topBarView.frame.origin.y + self.topBarView.frame.size.height, self.gsButtonVC.view.frame.size.width, self.gsButtonVC.view.frame.size.height)];
    self.gsButtonVC.delegate = self;
    [self.view addSubview:self.gsButtonVC.view];
    
    self.waypointConfigVC = [[DJIWaypointConfigViewController alloc] initWithNibName:@"DJIWaypointConfigViewController" bundle:[NSBundle mainBundle]];
    self.waypointConfigVC.view.alpha = 0;
    self.waypointConfigVC.view.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
    
    [self.waypointConfigVC.view setCenter:self.view.center];
    
    if ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad) //Check if it's using iPad and center the config view
    {
        self.waypointConfigVC.view.center = self.view.center;
    }

    self.waypointConfigVC.delegate = self;
    [self.view addSubview:self.waypointConfigVC.view];
}

-(void) registerApp
{
    //Please enter your App key in the info.plist file to register the app.
    [DJISDKManager registerAppWithDelegate:self];
}

#pragma mark DJISDKManagerDelegate Methods
- (void)appRegisteredWithError:(NSError *)error
{
    if (error){
        NSString *registerResult = [NSString stringWithFormat:@"Registration Error:%@", error.description];
        ShowMessage(@"Registration Result", registerResult, @"", nil, @"OK");
    }
    else{
#if ENTER_DEBUG_MODE
        [DJISDKManager enableBridgeModeWithBridgeAppIP:@"Please Enter Your Debug ID"];
#else
        [DJISDKManager startConnectionToProduct];
#endif
    }
}

- (void)productConnected:(DJIBaseProduct *)product
{
    if (product){
        DJIFlightController* flightController = [DemoUtility fetchFlightController];
        if (flightController) {
            flightController.delegate = self;
            ShowMessage(@"Product Connected", @"", @"", nil, @"OK");
        }
    }else{
        ShowMessage(@"Product disconnected", @"", @"", nil, @"OK");
    }
    
    //If this demo is used in China, it's required to login to your DJI account to activate the application. Also you need to use DJI Go app to bind the aircraft to your DJI account. For more details, please check this demo's tutorial.
    [[DJISDKManager userAccountManager] logIntoDJIUserAccountWithAuthorizationRequired:NO withCompletion:^(DJIUserAccountState state, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Login failed: %@", error.description);
        }
    }];
    
}

#pragma mark action Methods

-(DJIWaypointMissionOperator *)missionOperator {
    return [DJISDKManager missionControl].waypointMissionOperator;
}

- (void)focusMap
{
    if (CLLocationCoordinate2DIsValid(self.droneLocation)) {
        MKCoordinateRegion region = {0};
        region.center = self.droneLocation;
        region.span.latitudeDelta = 0.001;
        region.span.longitudeDelta = 0.001;
        
        [self.mapView setRegion:region animated:YES];
    }
}

#pragma mark CLLocation Methods
-(void) startUpdateLocation
{
    if ([CLLocationManager locationServicesEnabled]) {
        if (self.locationManager == nil) {
            self.locationManager = [[CLLocationManager alloc] init];
            self.locationManager.delegate = self;
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
            self.locationManager.distanceFilter = 0.1;
            if ([self.locationManager respondsToSelector:@selector(requestAlwaysAuthorization)]) {
                [self.locationManager requestAlwaysAuthorization];
            }
            [self.locationManager startUpdatingLocation];
        }
    }else
    {
        ShowMessage(@"Location Service is not available", @"", @"", nil, @"OK");
    }
}

#pragma mark UITapGestureRecognizer Methods
- (void)addWaypoints:(UITapGestureRecognizer *)tapGesture
{
    CGPoint point = [tapGesture locationInView:self.mapView];
    if(tapGesture.  state == UIGestureRecognizerStateEnded)
    {
        if (self.isEditingPoints)
        {
            [self.mapController addPoint:point withMapView:self.mapView];
        }
    }
}

#pragma mark - DJIWaypointConfigViewControllerDelegate Methods

- (void)cancelBtnActionInDJIWaypointConfigViewController:(DJIWaypointConfigViewController *)waypointConfigVC
{
    WeakRef(weakSelf);
    
    [UIView animateWithDuration:0.25 animations:^{
        WeakReturn(weakSelf);
        weakSelf.waypointConfigVC.view.alpha = 0;
    }];
}

- (void)showAlertViewWithTitle:(NSString *)title withMessage:(NSString *)message
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)finishBtnActionInDJIWaypointConfigViewController:(DJIWaypointConfigViewController *)waypointConfigVC
{
    WeakRef(weakSelf);
    
    [UIView animateWithDuration:0.25 animations:^{
        WeakReturn(weakSelf);
        weakSelf.waypointConfigVC.view.alpha = 0;
    }];
    
    for (int i = 0; i < self.waypointMission.waypointCount; i++) {
        DJIWaypoint* waypoint = [self.waypointMission waypointAtIndex:i];
        waypoint.altitude = [self.waypointConfigVC.altitudeTextField.text floatValue];
    }
    self.waypointMission.maxFlightSpeed = [self.waypointConfigVC.maxFlightSpeedTextField.text floatValue];
    self.waypointMission.autoFlightSpeed = [self.waypointConfigVC.autoFlightSpeedTextField.text floatValue];
    self.waypointMission.headingMode = (DJIWaypointMissionHeadingMode)self.waypointConfigVC.headingSegmentedControl.selectedSegmentIndex;
    [self.waypointMission setFinishedAction:(DJIWaypointMissionFinishedAction)self.waypointConfigVC.actionSegmentedControl.selectedSegmentIndex];

    [[self missionOperator] loadMission:self.waypointMission];
    
    WeakRef(target);
    
    [[self missionOperator] addListenerToFinished:self withQueue:dispatch_get_main_queue() andBlock:^(NSError * _Nullable error)
    {
        WeakReturn(target);
        
        if (error)
        {
            [target showAlertViewWithTitle:@"Mission Execution Failed" withMessage:[NSString stringWithFormat:@"%@", error.description]];
        }
        
        else
        {
            [target showAlertViewWithTitle:@"Mission Execution Finished" withMessage:nil];
        }
    }];
    
    [[self missionOperator] uploadMissionWithCompletion:^(NSError * _Nullable error)
    {
        if (error)
        {
            ShowMessage(@"Upload Mission failed", error.description, @"", nil, @"OK");
        }
        
        else
        {
            ShowMessage(@"Upload Mission Finished", @"", @"", nil, @"OK");
        }
    }];
}

#pragma mark - DJIGSButtonViewController Delegate Methods

- (void)stopBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    [[self missionOperator] stopMissionWithCompletion:^(NSError * _Nullable error) {
        if (error){
            NSString* failedMessage = [NSString stringWithFormat:@"Stop Mission Failed: %@", error.description];
            ShowMessage(@"", failedMessage, @"", nil, @"OK");
        }else
        {
            ShowMessage(@"Stop Mission Finished", @"", @"", nil, @"OK");
        }
    }];
}

- (void)clearBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    [self.mapController cleanAllPointsWithMapView:self.mapView];
}

- (void)focusMapBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    [self focusMap];
}

- (void)configBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    WeakRef(weakSelf);
    
    NSMutableArray* wayPoints = self.mapController.wayPoints;
    
    if (wayPoints == nil || wayPoints.count < 2) { //DJIWaypointMissionMinimumWaypointCount is 2.
        ShowMessage(@"No or not enough waypoints for mission", @"", @"", nil, @"OK");
        return;
    }
    
    [UIView animateWithDuration:0.25 animations:^{
        WeakReturn(weakSelf);
        weakSelf.waypointConfigVC.view.alpha = 1.0;
    }];
    
    if (self.waypointMission){
        [self.waypointMission removeAllWaypoints];
    }
    else{
        self.waypointMission = [[DJIMutableWaypointMission alloc] init];
    }
    
    for (int i = 0; i < wayPoints.count; i++) {
        CLLocation* location = [wayPoints objectAtIndex:i];

        if (CLLocationCoordinate2DIsValid(location.coordinate)) {
            DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
            [self.waypointMission addWaypoint:waypoint];
        }
    }
}

- (void)startBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    [[self missionOperator] startMissionWithCompletion:^(NSError * _Nullable error) {
        if (error){
            ShowMessage(@"Start Mission Failed", error.description, @"", nil, @"OK");
        }else
        {
            ShowMessage(@"Mission Started", @"", @"", nil, @"OK");
        }
    }];
}

- (void)switchToMode:(DJIGSViewMode)mode inGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    if (mode == DJIGSViewMode_EditMode) {
        [self focusMap];
    }
}

- (void)addBtn:(UIButton *)button withActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    if (self.isEditingPoints) {
        self.isEditingPoints = NO;
        [button setTitle:@"Add" forState:UIControlStateNormal];
    }else
    {
        self.isEditingPoints = YES;
        [button setTitle:@"Finished" forState:UIControlStateNormal];
    }
}

- (void) configureMission
{
    for (int i = 0; i < self.waypointMission.waypointCount; i++)
    {
        DJIWaypoint* waypoint = [self.waypointMission waypointAtIndex:i];
        waypoint.altitude = 30.0; //[coordinates[i][2] floatValue];
    }
    
    self.waypointMission.maxFlightSpeed = MAX_FLIGHT_SPEED;
    self.waypointMission.autoFlightSpeed = AUTO_FLIGHT_SPEED;
    
    self.waypointMission.headingMode = 0;
    [self.waypointMission setFinishedAction: 0];
    
    [[self missionOperator] loadMission:self.waypointMission];
    
    WeakRef(target);
    
    [[self missionOperator] addListenerToFinished:self withQueue:dispatch_get_main_queue() andBlock:^(NSError * _Nullable error)
     {
         WeakReturn(target);
         
         if (error)
         {
             [target showAlertViewWithTitle:@"Mission Execution Failed" withMessage:[NSString stringWithFormat:@"%@", error.description]];
         }
         
         else
         {
             [target showAlertViewWithTitle:@"Mission Execution Finished" withMessage:nil];
         }
     }];
}

- (void) uploadAndExecuteMission
/**
Adapted the answer of Ken Thomases from <https://stackoverflow.com/questions/50534982/objective-c-sequentially-executing-two-completion-blocks/50536092?noredirect=1#comment88094948_50536092>
**/
{
    [[self missionOperator] uploadMissionWithCompletion:^(NSError * _Nullable error) {
        if (error)
        {
            ShowMessage(@"Upload Mission failed", error.description, @"", nil, @"OK");
        }
        
        else
        {
            ShowMessage(@"Upload Mission Started", @"", @"", nil, @"OK");
            
            [[self missionOperator] addListenerToUploadEvent:self withQueue:nil andBlock:^(DJIWaypointMissionUploadEvent *event)
            {
                if (event.currentState == DJIWaypointMissionStateReadyToExecute)
                {
                    [[self missionOperator] startMissionWithCompletion:^(NSError * _Nullable error) {
                        if (error)
                        {
                            ShowMessage(@"Start Mission Failed", error.description, @"", nil, @"OK");
                        }
                        else
                        {
                            ShowMessage(@"Mission Started", @"", @"", nil, @"OK");
                        }
                    }];
                }
                
                else if (event.error)
                {
                    ShowMessage(@"Upload Mission failed", event.error.description, @"", nil, @"OK");
                }
            }];
        }
    }];
}

- (void)initiateAutopilotBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    //Load coordinates.
    NSError *error = nil;
    
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *filePath = [bundle pathForResource:@"1.json" ofType:nil];
    NSData *data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&error];
    
    NSDictionary *JSONObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    NSArray *coordinates = [JSONObject objectForKey:@"coordinates"];
     
    //Convert to waypoints.
    self.waypointMission = [[DJIMutableWaypointMission alloc] init];
    
    for (int i = 0; i < coordinates.count; i++)
    {
        double latitude = [coordinates[i][0] floatValue];
        double longitude = [coordinates[i][1] floatValue];
        CLLocationCoordinate2D currentCoordinate = CLLocationCoordinate2DMake(latitude, longitude);
        CLLocation *location = [[CLLocation alloc] initWithLatitude:currentCoordinate.latitude longitude:currentCoordinate.longitude];
        [_editPoints addObject:location];
        MKPointAnnotation* annotation = [[MKPointAnnotation alloc] init];
        annotation.coordinate = location.coordinate;
        [_mapView addAnnotation:annotation];
        
        NSMutableArray <NSNumber *> *newCoordinate;
        
        NSNumber *currentLatitude = [NSNumber numberWithDouble: currentCoordinate.latitude];
        NSNumber *currentLongitude = [NSNumber numberWithDouble: currentCoordinate.longitude];
        
        [newCoordinate addObject: currentLatitude];
        [newCoordinate addObject: currentLongitude];
        
        [allCoordinates addObject: newCoordinate];
        
        if (CLLocationCoordinate2DIsValid(location.coordinate))
        {
            DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
            [self.waypointMission addWaypoint:waypoint];
        }
    }
    
    [[self missionOperator] addListenerToExecutionEvent:self withQueue:nil andBlock:^(DJIWaypointMissionExecutionEvent *event)
     {
         self->missionProgress = [NSNumber numberWithInteger: event.progress.targetWaypointIndex];;
     }];
    
    [self configureMission];
    [self uploadAndExecuteMission];
}

- (void)missionStateBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    NSString *state = [NSString stringWithFormat: @"%ld", (long)[[self missionOperator] currentState]];
    ShowMessage(@"Current State", @"", state, nil, @"OK");
}

- (void)addMoreBtnActionInGSButtonVC:(DJIGSButtonViewController *)GSBtnVC
{
    NSInteger indexInt = [self->missionProgress integerValue];
    
    //For outputting the current progress
    //NSString *indexString = [self->missionProgress stringValue];
    //ShowMessage(indexString, @"", @"", nil, @"OK");
    
    NSArray<DJIWaypoint *> *originalWaypoints = self.waypointMission.allWaypoints;

    NSMutableArray *newCoordinates = [[NSMutableArray alloc] init];
    
    NSError *error = nil;
    
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *filePath = [bundle pathForResource:@"2.json" ofType:nil];
    NSData *data = [NSData dataWithContentsOfFile:filePath options:NSDataReadingMappedIfSafe error:&error];
    
    NSDictionary *JSONObject = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
    NSArray *jsonCoordinates = [JSONObject objectForKey:@"coordinates"];
    
    for (int i = 0; i < jsonCoordinates.count; i++)
    {
        NSArray<NSNumber *> *newCoordinate = jsonCoordinates[i];
        [newCoordinates addObject: newCoordinate];
    }
  
    int state = [[self missionOperator] currentState];
    if (state == 3)
    {
        [self.waypointMission removeAllWaypoints];
        //[self.mapController cleanAllPointsWithMapView:self.mapView];
        //self.waypointMission = [[DJIMutableWaypointMission alloc] init];
        
        for (int i = 0; i < newCoordinates.count; i++)
        {
            double latitude = [newCoordinates[i][0] floatValue];
            double longitude = [newCoordinates[i][1] floatValue];
            CLLocationCoordinate2D currentCoordinate = CLLocationCoordinate2DMake(latitude, longitude);
            CLLocation *location = [[CLLocation alloc] initWithLatitude:currentCoordinate.latitude longitude:currentCoordinate.longitude];
            
            [self->_editPoints addObject:location];
            MKPointAnnotation* annotation = [[MKPointAnnotation alloc] init];
            annotation.coordinate = location.coordinate;
            [self->_mapView addAnnotation:annotation];
            
            NSMutableArray <NSNumber *> *newCoordinate;
            
            NSNumber *currentLatitude = [NSNumber numberWithDouble: currentCoordinate.latitude];
            NSNumber *currentLongitude = [NSNumber numberWithDouble: currentCoordinate.longitude];
            
            [newCoordinate addObject: currentLatitude];
            [newCoordinate addObject: currentLongitude];
            
            [self->allCoordinates addObject: newCoordinate];
            
            if (CLLocationCoordinate2DIsValid(location.coordinate))
            {
                DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
                [self.waypointMission addWaypoint:waypoint];
            }
        }
        
        [self configureMission];
        [self uploadAndExecuteMission];
    }
    
    if (state == 6)
    {
        [[self missionOperator] stopMissionWithCompletion:^(NSError * _Nullable error)
         {
             if (error)
             {
                 //NSString* failedMessage = [NSString stringWithFormat:@"Stop Mission Failed: %@", error.description];
                 //ShowMessage(@"", failedMessage, @"", nil, @"OK");
                 ;
             }
             
             else
             {
                 ;
             }
         }];
        
        [[self missionOperator] addListenerToExecutionEvent:self withQueue:nil andBlock:^(DJIWaypointMissionExecutionEvent *event)
         {
             if (event.currentState == DJIWaypointMissionStateReadyToUpload)
             {
                 if (indexInt < originalWaypoints.count)
                 {
                     for (NSInteger i = originalWaypoints.count - 1; i >= indexInt; i--)
                     {
                         NSNumber *waypointlatitude = [NSNumber numberWithDouble: originalWaypoints[i].coordinate.latitude];
                         NSNumber *waypointLongitude = [NSNumber numberWithDouble: originalWaypoints[i].coordinate.longitude];
                         NSMutableArray <NSNumber *> *coordinate = [[NSMutableArray alloc] init];
                         [coordinate addObject: waypointlatitude];
                         [coordinate addObject: waypointLongitude];
                         [newCoordinates insertObject:coordinate atIndex:0];
                     }
                 }
                 
                 else if (indexInt > originalWaypoints.count)
                 {
                     for (NSInteger i = 0; i < indexInt - originalWaypoints.count; i++)
                     {
                         [newCoordinates removeObjectAtIndex: i];
                     }
                 }
                 
                 else
                 {
                     ;
                 }
                 
                 [self.waypointMission removeAllWaypoints];
                 //[self.mapController cleanAllPointsWithMapView:self.mapView];
                 //self.waypointMission = [[DJIMutableWaypointMission alloc] init];
                 
                 for (int i = 0; i < newCoordinates.count; i++)
                 {
                     double latitude = [newCoordinates[i][0] floatValue];
                     double longitude = [newCoordinates[i][1] floatValue];
                     CLLocationCoordinate2D currentCoordinate = CLLocationCoordinate2DMake(latitude, longitude);
                     CLLocation *location = [[CLLocation alloc] initWithLatitude:currentCoordinate.latitude longitude:currentCoordinate.longitude];
                     
                     [self->_editPoints addObject:location];
                     MKPointAnnotation* annotation = [[MKPointAnnotation alloc] init];
                     annotation.coordinate = location.coordinate;
                     [self->_mapView addAnnotation:annotation];
                     
                     NSMutableArray <NSNumber *> *newCoordinate;
                     
                     NSNumber *currentLatitude = [NSNumber numberWithDouble: currentCoordinate.latitude];
                     NSNumber *currentLongitude = [NSNumber numberWithDouble: currentCoordinate.longitude];
                     
                     [newCoordinate addObject: currentLatitude];
                     [newCoordinate addObject: currentLongitude];
                     
                     [self->allCoordinates addObject: newCoordinate];
                     
                     if (CLLocationCoordinate2DIsValid(location.coordinate))
                     {
                         DJIWaypoint* waypoint = [[DJIWaypoint alloc] initWithCoordinate:location.coordinate];
                         [self.waypointMission addWaypoint:waypoint];
                     }
                 }
                 
                 [self configureMission];
                 [self uploadAndExecuteMission];
             }
         }];
    }
}

#pragma mark - CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations
{
    CLLocation* location = [locations lastObject];
    self.userLocation = location.coordinate;
    
    for (int i = 0; i < allCoordinates.count - 1; i++)
    {
        CLLocationCoordinate2D coordinate1 = CLLocationCoordinate2DMake([allCoordinates[i][0] doubleValue], [allCoordinates[i][1] doubleValue]);
        CLLocationCoordinate2D coordinate2 = CLLocationCoordinate2DMake([allCoordinates[i+1][0] doubleValue], [allCoordinates[i+1][1] doubleValue]);
        
        MKMapPoint * pointsArray = malloc(sizeof(CLLocationCoordinate2D)*2);
        
        pointsArray[0]= MKMapPointForCoordinate(coordinate1);
        pointsArray[1]= MKMapPointForCoordinate(coordinate2);
        
        MKPolyline *  routeLine = [MKPolyline polylineWithPoints:pointsArray count:2];
        free(pointsArray);
        
        [self.mapView addOverlay:routeLine];
    }
}

#pragma mark MKMapViewDelegate Method
- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id <MKAnnotation>)annotation
{
    if ([annotation isKindOfClass:[MKPointAnnotation class]])
    {
        MKPinAnnotationView* pinView = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"Pin_Annotation"];
        pinView.pinTintColor = [UIColor purpleColor];
        return pinView;
    }
    
    else if ([annotation isKindOfClass:[DJIAircraftAnnotation class]])
    {
        DJIAircraftAnnotationView* annoView = [[DJIAircraftAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"Aircraft_Annotation"];
        ((DJIAircraftAnnotation*)annotation).annotationView = annoView;
        return annoView;
    }
    return nil;
}

#pragma mark DJIFlightControllerDelegate

- (void)flightController:(DJIFlightController *)fc didUpdateState:(DJIFlightControllerState *)state
{
    self.droneLocation = state.aircraftLocation.coordinate;
    self.modeLabel.text = state.flightModeString;
    self.gpsLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)state.satelliteCount];
    self.vsLabel.text = [NSString stringWithFormat:@"%0.1f M/S",state.velocityZ];
    self.hsLabel.text = [NSString stringWithFormat:@"%0.1f M/S",(sqrtf(state.velocityX*state.velocityX + state.velocityY*state.velocityY))];
    self.altitudeLabel.text = [NSString stringWithFormat:@"%0.1f M",state.altitude];
    
    [self.mapController updateAircraftLocation:self.droneLocation withMapView:self.mapView];
    double radianYaw = RADIAN(state.attitude.yaw);
    [self.mapController updateAircraftHeading:radianYaw];
}

@end
