#import "UIBezierPath+Length.h"

const NSString *kInfoCurrentPointKey = @"kInfoCurrentPointKey";
const NSString *kInfoSubpathsKey = @"kInfoSubpathsKey";

struct BezierSubpath {
    CGPoint startPoint;
    CGPoint controlPoint1;
    CGPoint controlPoint2;
    CGPoint endPoint;
    CGFloat length;
    CGPathElementType type;
};
typedef struct BezierSubpath BezierSubpath;


id encodeSubpath(BezierSubpath subpath) {
    return [NSValue valueWithBytes:&subpath objCType:@encode(struct BezierSubpath)];
}

BezierSubpath decodeSubpath(id subpath) {
    struct BezierSubpath newSubpath;
    
    if (strcmp([subpath objCType], @encode(struct BezierSubpath)) == 0) {
        [subpath getValue:&newSubpath];
    }
    
    return newSubpath;
}


@implementation UIBezierPath (Length)

- (CGFloat)length {
    return [self calculateLength];
}

- (CGFloat)calculateLength {
    __block CGFloat length = 0;
    [[self extractSubpaths] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        BezierSubpath subpath = decodeSubpath(obj);
        
        length += subpath.length;
    }];
    
    return length;
}

- (CGPoint)pointAtPercentOfLength:(CGFloat)percent {
    NSArray *subpaths = [self extractSubpaths];
    
    __block CGFloat length = 0;
    [subpaths enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        BezierSubpath subpath = decodeSubpath(obj);
        
        length += subpath.length;
    }];
    
    CGFloat pointLocationInPath = length * percent;
    __block CGFloat currentLength = 0;
    
    __block BezierSubpath subpathContainingPoint;
    
    [subpaths enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        BezierSubpath subpath = decodeSubpath(obj);
        
        if (currentLength + subpath.length >= pointLocationInPath) {
            subpathContainingPoint = subpath;
            
            *stop = YES;
        } else {
            currentLength += subpath.length;
        }
    }];
    
    
    CGFloat lengthInSubpath = pointLocationInPath - currentLength;
    CGFloat t = lengthInSubpath / subpathContainingPoint.length;
    
    return [self pointAtPercent:t ofSubpath:subpathContainingPoint];
}

- (NSArray *)extractSubpaths {
    NSMutableArray *subpaths = [NSMutableArray array];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    [info setObject:[NSValue valueWithCGPoint:CGPointZero] forKey:kInfoCurrentPointKey];
    [info setObject:subpaths forKey:kInfoSubpathsKey];
    
    CGPathRef path = self.CGPath;
    
    CGPathApply(path, (__bridge void *)(info), pathApplierFunction);
    
    return subpaths;
}

- (CGPoint)pointAtPercent:(CGFloat)t ofSubpath:(BezierSubpath)subpath {
    CGPoint p = CGPointZero;
    
    switch (subpath.type) {
        case kCGPathElementAddLineToPoint:
            p = linearBezierPoint(t, subpath.startPoint, subpath.endPoint);
            break;
            
        case kCGPathElementAddQuadCurveToPoint:
            p = quadBezierPoint(t, subpath.startPoint, subpath.controlPoint1, subpath.endPoint);
            break;
            
        case kCGPathElementAddCurveToPoint:
            p = cubicBezierPoint(t, subpath.startPoint, subpath.controlPoint1, subpath.controlPoint2, subpath.endPoint);
            break;
            
        default:
            break;
    }
    
    return p;
}

void pathApplierFunction(void *info, const CGPathElement *element) {
    NSMutableDictionary *infoDictionary = (__bridge NSMutableDictionary *)info;
    
    CGPoint currentPoint = [[infoDictionary objectForKey:kInfoCurrentPointKey] CGPointValue];
    NSMutableArray *subpaths = [infoDictionary objectForKey:kInfoSubpathsKey];
    
    CGPathElementType type = element->type;
    CGPoint *points = element->points;
    
    CGFloat subLength = 0;
    CGPoint endPoint = CGPointZero;
    
    
    BezierSubpath subpath;
    subpath.type = type;
    subpath.startPoint = currentPoint;
    
    
    /*
     *  All paths, no matter how complex, are created through a combination of these path elements.
     */
    
    switch (type) {
        case kCGPathElementMoveToPoint:
            
            endPoint = points[0];
            
            break;
            
        case kCGPathElementCloseSubpath:
            
            break;
            
        case kCGPathElementAddLineToPoint:
            
            endPoint = points[0];
            
            subLength = linearLineLength(currentPoint, endPoint);
            
            break;
            
        case kCGPathElementAddQuadCurveToPoint:
            
            endPoint = points[1];
            CGPoint controlPoint = points[0];
            
            subLength = quadCurveLength(currentPoint, endPoint, controlPoint);
            
            subpath.controlPoint1 = controlPoint;
            
            break;
            
        case kCGPathElementAddCurveToPoint:
            
            endPoint = points[2];
            CGPoint controlPoint1 = points[0];
            CGPoint controlPoint2 = points[1];
            
            subLength = cubicCurveLength(currentPoint, endPoint, controlPoint1, controlPoint2);
            
            subpath.controlPoint1 = controlPoint1;
            subpath.controlPoint2 = controlPoint2;
            
            break;
    }
    
    
    subpath.length = subLength;
    subpath.endPoint = endPoint;
    
    if (type != kCGPathElementMoveToPoint) {
        [subpaths addObject:encodeSubpath(subpath)];
    }
    
    [infoDictionary setObject:[NSValue valueWithCGPoint:endPoint] forKey:kInfoCurrentPointKey];
}



CGFloat linearLineLength(CGPoint fromPoint, CGPoint toPoint) {
    return sqrtf(powf(toPoint.x - fromPoint.x, 2) + powf(toPoint.y - fromPoint.y, 2));
}


CGFloat quadCurveLength(CGPoint fromPoint, CGPoint toPoint, CGPoint controlPoint) {
    int iterations = 100;
    CGFloat length = 0;
    
    for (int idx=0; idx < iterations; idx++) {
        float t = idx * (1.0 / iterations);
        float tt = t + (1.0 / iterations);
        
        CGPoint p = quadBezierPoint(t, fromPoint, controlPoint, toPoint);
        CGPoint pp = quadBezierPoint(tt, fromPoint, controlPoint, toPoint);
        
        length += linearLineLength(p, pp);
    }
    
    return length;
}

CGFloat cubicCurveLength(CGPoint fromPoint, CGPoint toPoint, CGPoint controlPoint1, CGPoint controlPoint2) {
    int iterations = 100;
    CGFloat length = 0;
    
    for (int idx=0; idx < iterations; idx++) {
        float t = idx * (1.0 / iterations);
        float tt = t + (1.0 / iterations);
        
        CGPoint p = cubicBezierPoint(t, fromPoint, controlPoint1, controlPoint2, toPoint);
        CGPoint pp = cubicBezierPoint(tt, fromPoint, controlPoint1, controlPoint2, toPoint);
        
        length += linearLineLength(p, pp);
    }
    
    
    return length;
}

CGPoint linearBezierPoint(float t, CGPoint start, CGPoint end) {
    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    
    CGFloat px = start.x + (t * dx);
    CGFloat py = start.y + (t * dy);
    
    return CGPointMake(px, py);
}

CGPoint quadBezierPoint(float t, CGPoint start, CGPoint c1, CGPoint end) {
    CGFloat x = QuadBezier(t, start.x, c1.x, end.x);
    CGFloat y = QuadBezier(t, start.y, c1.y, end.y);
    
    return CGPointMake(x, y);
}

CGPoint cubicBezierPoint(float t, CGPoint start, CGPoint c1, CGPoint c2, CGPoint end) {
    CGFloat x = CubicBezier(t, start.x, c1.x, c2.x, end.x);
    CGFloat y = CubicBezier(t, start.y, c1.y, c2.y, end.y);
    
    return CGPointMake(x, y);
}

/*
 *  http://ericasadun.com/2013/03/25/calculating-bezier-points/
 */
float CubicBezier(float t, float start, float c1, float c2, float end) {
    CGFloat t_ = (1.0 - t);
    CGFloat tt_ = t_ * t_;
    CGFloat ttt_ = t_ * t_ * t_;
    CGFloat tt = t * t;
    CGFloat ttt = t * t * t;
    
    return start * ttt_
    + 3.0 *  c1 * tt_ * t
    + 3.0 *  c2 * t_ * tt
    + end * ttt;
}

/*
 *  http://ericasadun.com/2013/03/25/calculating-bezier-points/
 */
float QuadBezier(float t, float start, float c1, float end) {
    CGFloat t_ = (1.0 - t);
    CGFloat tt_ = t_ * t_;
    CGFloat tt = t * t;
    
    return start * tt_
    + 2.0 *  c1 * t_ * t
    + end * tt;
}

@end
