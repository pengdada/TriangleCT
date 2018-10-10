
#include "graph_ray_projection.hpp"


// This flag activates timing of the code
#define DEBUG_TIME 1
#define EPSILON 0.000001

// Cuda error checking.
#define gpuErrchk(ans) { gpuAssert((ans), __FILE__, __LINE__); }

inline void gpuAssert(cudaError_t code, const char *file, int line, bool abort=true)
{
    if (code != cudaSuccess)
    {
        mexPrintf("GPUassert: %s %s %d\n", cudaGetErrorString(code), file, line);
        if (abort){
            cudaDeviceReset();
            mexErrMsgIdAndTxt("MEX:graph_ray_projections", ".");
        }
    }
}

__global__ void testKernel(const Graph * graph,float * d_res){
    d_res[0]=(float)graph->node[1].position[0];
    
};
__device__ __inline__ vec3d cross(const vec3d a,const vec3d b)
{
    vec3d c;
    c.x= a.y*b.z - a.z*b.y;
    c.y= a.z*b.x - a.x*b.z;
    c.z= a.x*b.y - a.y*b.x;
    return c;
}
/*********************************************************************
 *********************** Dot product in CUDA ************************
 ********************************************************************/
__device__ __inline__ double dot(const vec3d a, const vec3d b)
{
    
    return a.x*b.x+a.y*b.y+a.z*b.z;
}



__device__ __inline__ float max4(float *t,int* indM){
    float max=0;
    *indM=-1;
    for(int i=0;i<4;i++){
        if (t[i]>max){
            max=t[i];
            *indM=i;
        }
    }
    return max;
}

__device__ __inline__ float min4nz(float *t){
    float min=1;
    for(int i=0;i<4;i++)
        min=(t[i]<min && t[i]!=0)?t[i]:min;
        return min;
}

__device__ __inline__ int nnz(float *t){
    int nz=0;
    for(int i=0;i<4;i++){
        if(t[i]>0){
            nz++;
        }
    }
    return nz;
    
}

__device__ vec3 double2float(vec3d in){
  vec3 out;
  out.x=(float)in.x;
  out.y=(float)in.y;
  out.z=(float)in.z;
  return out;
}
__device__ vec3d float2double(vec3 in){
  vec3d out;
  out.x=(double)in.x;
  out.y=(double)in.y;
  out.z=(double)in.z;
  return out;
}
/*********************************************************************
 *********************** Moller trumbore ************************
 ********************************************************************/
__device__ __inline__ float moller_trumbore(const vec3d ray1, const vec3d ray2,
        const vec3d trip1,const vec3d trip2,const vec3d trip3, const float safetyEpsilon){
    
//     vec3 fray1,fray2,ftrip1,ftrip2,ftrip3;
//     fray1=double2float(ray1);
//     fray2=double2float(ray2);
    
    vec3d direction,e1,e2;
    
    direction.x=ray2.x-ray1.x;     direction.y=ray2.y-ray1.y;     direction.z=ray2.z-ray1.z;
    e1.x       =trip2.x-trip1.x;   e1.y       =trip2.y-trip1.y;   e1.z       =trip2.z-trip1.z;
    e2.x       =trip3.x-trip1.x;   e2.y       =trip3.y-trip1.y;   e2.z       =trip3.z-trip1.z;
    
    
    vec3d q=cross(direction,e2);
    double a=dot(e1,q);
    if ((a>-EPSILON) & (a<EPSILON)){
        // the vector is parallel to the plane (the intersection is at infinity)
        return 0.0f;
    }
    
    double f=1/a;
    vec3d s;
    
    s.x=ray1.x-trip1.x;     s.y=ray1.y-trip1.y;     s.z=ray1.z-trip1.z;
    double u=f*dot(s,q);
    
    if (u<0.0-safetyEpsilon){
        // the intersection is outside of the triangle
        return 0.0f;
    }
    
    vec3d r=cross(s,e1);
    double v= f*dot(direction,r);
    
    if (v<0.0-safetyEpsilon || (u+v)>1.0+safetyEpsilon){
        // the intersection is outside of the triangle
        return 0.0;
    }
//     mexPrintf("%.16f %.16f %.16f\n",q.x,q.y,q.z);
//     mexPrintf("%.16f  %.16f %.16f %.16f %.16f\n",a,f,u,v,f*dot(e2,r));
    return f*dot(e2,r);
    
    
    
}

/*********************************************************************
 **********************Tetra-line intersection************************
 ********************************************************************/

// TODO: check if adding if-clauses after each moller trumbore is better of worse.
__device__ __inline__ bool tetraLineIntersect(const unsigned long *elements,const double *vertices,
        const vec3d ray1, const vec3d ray2,
        const unsigned long elementId,float *t,bool computelenght,const float safetyEpsilon){
    
    unsigned long auxNodeId[4];
    auxNodeId[0]=elements[elementId*4+0];
    auxNodeId[1]=elements[elementId*4+1];
    auxNodeId[2]=elements[elementId*4+2];
    auxNodeId[3]=elements[elementId*4+3];
    
    
    vec3d triN1,triN2,triN3;
    
    float l1,l2,l3,l4;
    
    ///////////////////////////////////////////////////////////////////////
    // As modular arithmetic is bad on GPUs (flop-wise), I manually unroll the loop
    //for (int i=0;i<4;i++)
    ///////////////////////////////////////////////////////////////////////
    // Triangle
    triN1.x=vertices[auxNodeId[0]*3+0];    triN1.y=vertices[auxNodeId[0]*3+1];    triN1.z=vertices[auxNodeId[0]*3+2];
    triN2.x=vertices[auxNodeId[1]*3+0];    triN2.y=vertices[auxNodeId[1]*3+1];    triN2.z=vertices[auxNodeId[1]*3+2];
    triN3.x=vertices[auxNodeId[2]*3+0];    triN3.y=vertices[auxNodeId[2]*3+1];    triN3.z=vertices[auxNodeId[2]*3+2];
    //compute
    l1=moller_trumbore(ray1,ray2,triN1,triN2,triN3,safetyEpsilon);
    // Triangle
    triN1.x=vertices[auxNodeId[0]*3+0];    triN1.y=vertices[auxNodeId[0]*3+1];    triN1.z=vertices[auxNodeId[0]*3+2];
    triN2.x=vertices[auxNodeId[1]*3+0];    triN2.y=vertices[auxNodeId[1]*3+1];    triN2.z=vertices[auxNodeId[1]*3+2];
    triN3.x=vertices[auxNodeId[3]*3+0];    triN3.y=vertices[auxNodeId[3]*3+1];    triN3.z=vertices[auxNodeId[3]*3+2];
    //compute
    l2=moller_trumbore(ray1,ray2,triN1,triN2,triN3,safetyEpsilon);
    // Triangle
    triN1.x=vertices[auxNodeId[0]*3+0];    triN1.y=vertices[auxNodeId[0]*3+1];    triN1.z=vertices[auxNodeId[0]*3+2];
    triN2.x=vertices[auxNodeId[2]*3+0];    triN2.y=vertices[auxNodeId[2]*3+1];    triN2.z=vertices[auxNodeId[2]*3+2];
    triN3.x=vertices[auxNodeId[3]*3+0];    triN3.y=vertices[auxNodeId[3]*3+1];    triN3.z=vertices[auxNodeId[3]*3+2];
    //compute
    l3=moller_trumbore(ray1,ray2,triN1,triN2,triN3,safetyEpsilon);
    // Triangle
    triN1.x=vertices[auxNodeId[1]*3+0];    triN1.y=vertices[auxNodeId[1]*3+1];    triN1.z=vertices[auxNodeId[1]*3+2];
    triN2.x=vertices[auxNodeId[2]*3+0];    triN2.y=vertices[auxNodeId[2]*3+1];    triN2.z=vertices[auxNodeId[2]*3+2];
    triN3.x=vertices[auxNodeId[3]*3+0];    triN3.y=vertices[auxNodeId[3]*3+1];    triN3.z=vertices[auxNodeId[3]*3+2];
    //compute
    l4=moller_trumbore(ray1,ray2,triN1,triN2,triN3,safetyEpsilon);
    
    //dump
    if(!computelenght){
        return (l1!=0.0)|(l2!=0.0)|(l3!=0.0)|(l4!=0.0);
    }else{
        //fuck branches, but what can I do ....
        if ((l1==0.0)&&(l2==0.0)&&(l3==0.0)&&(l4==0.0)){
            t[0]=0.0;t[1]=0.0;t[2]=0.0;t[3]=0.0;
            return false;
        }else{
            t[0]=l1;t[1]=l2;t[2]=l3;t[3]=l4;
            // find which one is the intersection
            return true;
        }
    }
}


__device__ bool rayBoxIntersect(const vec3d ray1, const vec3d ray2,const vec3d nodemin, const vec3d nodemax){
    vec3 direction;
    direction.x=ray2.x-ray1.x;
    direction.y=ray2.y-ray1.y;
    direction.z=ray2.z-ray1.z;
    
    float tmin,tymin,tzmin;
    float tmax,tymax,tzmax;
    if (direction.x >= 0){
        tmin = (nodemin.x - ray1.x) / direction.x;
        tmax = (nodemax.x - ray1.x) / direction.x;
        
    }else{
        tmin = (nodemax.x - ray1.x) / direction.x;
        tmax = (nodemin.x - ray1.x) / direction.x;
    }
    
    if (direction.y >= 0){
        tymin = (nodemin.y - ray1.y) / direction.y;
        tymax = (nodemax.y - ray1.y) / direction.y;
    }else{
        tymin = (nodemax.y - ray1.y) / direction.y;
        tymax = (nodemin.y - ray1.y) / direction.y;
    }
    
    if ( (tmin > tymax) || (tymin > tmax) ){
        return false;
    }
    
    if (tymin > tmin){
        tmin = tymin;
    }
    
    if (tymax < tmax){
        tmax = tymax;
    }
    
    if (direction.z >= 0){
        tzmin = (nodemin.z - ray1.z) / direction.z;
        tzmax = (nodemax.z - ray1.z) / direction.z;
    }else{
        tzmin = (nodemax.z - ray1.z) / direction.z;
        tzmax = (nodemin.z - ray1.z) / direction.z;
    }
    
    
    if ((tmin > tzmax) || (tzmin > tmax)){
        return false;
    }
// If we wanted the ts as output
// if (tzmin > tmin){
//     tmin = tzmin;
// }
//
// if (tzmax < tmax){
//     tmax = tzmax;
// }
    
    return true;
}
/*********************************************************************
 ******Fucntion to detect the first triangle to expand the graph******
 ********************************************************************/

__global__ void initXrays(const unsigned long* elements, const double* vertices,
        const unsigned long *boundary,const unsigned long nboundary,
        float * d_res, Geometry geo,
        const vec3d source,const vec3d deltaU,const vec3d deltaV,const vec3d uvOrigin,const vec3d nodemin,const vec3d nodemax)
{
    
    
    unsigned long  y = blockIdx.y * blockDim.y + threadIdx.y;
    unsigned long  x = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned long  idx =  x  * geo.nDetecV + y;
    if ((x>= geo.nDetecU) || (y>= geo.nDetecV))
        return;
    
    // Read initial position.
    // Is having this here going to speed up because the below maths can be done while waiting to read?
    // Create ray
    unsigned int pixelV =(unsigned int)geo.nDetecV- y-1;
    unsigned int pixelU =(unsigned int) x;

    vec3d det;
    
    det.x=(uvOrigin.x+pixelU*deltaU.x+pixelV*deltaV.x);
    det.y=(uvOrigin.y+pixelU*deltaU.y+pixelV*deltaV.y);
    det.z=(uvOrigin.z+pixelU*deltaU.z+pixelV*deltaV.z);
    
    bool crossBound=rayBoxIntersect(source, det, nodemin,nodemax);
    if (!crossBound){
        d_res[idx]=-1.0f;
        return;
    }
    
    
    
    // Check intersection with boundary
    unsigned long notintersect=nboundary;
    float t[4];
    float t1,tinter=10000.0f;
    float safetyEpsilon=0.0000001f;
    unsigned long crossingID=0;
    while(notintersect==nboundary){
        notintersect=0;
        for(unsigned long i=0 ;i<nboundary;i++){
            tetraLineIntersect(elements,vertices,source,det,boundary[i],t,true,safetyEpsilon);
            
            if (nnz(t)==0){
                notintersect++;
            }else{
                
                t1=min4nz(t);
                
                if (t1<tinter){
                    
                    tinter=t1;
                    crossingID=i;
                }
            }
        }
        safetyEpsilon=safetyEpsilon*10;
    }
    d_res[idx]=(float)crossingID;
    
    // Should I put the kernels together, or separate? TODO
    
}
/*********************************************************************
 ******************The mein projection fucntion **********************
 ********************************************************************/

__global__ void graphProject(const unsigned long *elements, const double *vertices,const unsigned long *boundary,const long *neighbours, const float * d_image, float * d_res, Geometry geo,
        vec3d source, vec3d deltaU, vec3d deltaV, vec3d uvOrigin){
    
    unsigned long  y = blockIdx.y * blockDim.y + threadIdx.y;
    unsigned long  x = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned long  idx =  x  * geo.nDetecV + y;
    if ((x>= geo.nDetecU) || (y>= geo.nDetecV))
        return;
    
    // Read initial position.
    // Is having this here going to speed up because the below maths can be done while waiting to read?
    // Create ray
    unsigned int pixelV =(unsigned int)geo.nDetecV- y-1;
    unsigned int pixelU =(unsigned int) x;

    
    // Read initial position.
    // Is having this here going to speed up because the below maths can be done while waiting to read?
    long current_element=(long)d_res[idx];
    long previous_element;
    long aux_element;
    // Create ray

    vec3d det;
    
    det.x=(uvOrigin.x+pixelU*deltaU.x+pixelV*deltaV.x);
    det.y=(uvOrigin.y+pixelU*deltaU.y+pixelV*deltaV.y);
    det.z=(uvOrigin.z+pixelU*deltaU.z+pixelV*deltaV.z);
    
    if (current_element==-1){
        //no need to do stuff
        d_res[idx]=0.0f;
        return;
    }
    
    float result=0.0f;
    
    float length,t1,t2;
    float t[4];
    int indM;
    bool isIntersect;
    
    float safeEpsilon=0.00001f;
    isIntersect=tetraLineIntersect(elements,vertices,source,det,boundary[current_element],t,true,0.0f);
    while(!isIntersect){
        isIntersect=tetraLineIntersect(elements,vertices,source,det,boundary[current_element],t,true,safeEpsilon);
        if (nnz(t)<=1){
            isIntersect=false;
            safeEpsilon*=10;
        }
    }
    safeEpsilon=0.00001f;
    t2=max4(t,&indM);
    t1=min4nz(t);
//      mexPrintf("%.16f %.16f\n",t2,t1);
//     mexPrintf("%.16f %.16f %.16f\n",source.x,source.y,source.z);
//     mexPrintf("%.16f %.16f %.16f\n",det.x,det.y,det.z);
    
    
    vec3d direction,p1,p2;
    direction.x=det.x-source.x;     direction.y=det.y-source.y;     direction.z=det.z-source.z;
    p2.x=direction.x* (t2);  p2.y=direction.y* (t2); p2.z=direction.z* (t2);
    p1.x=direction.x* (t1);  p1.y=direction.y* (t1); p1.z=direction.z* (t1);
    
    length=sqrt((p2.x-p1.x)*(p2.x-p1.x)+(p2.y-p1.y)*(p2.y-p1.y)+(p2.z-p1.z)*(p2.z-p1.z));
    
    
    
    result=d_image[boundary[current_element]]*length;
    
    if(t1==t2){
        
        aux_element=neighbours[boundary[current_element]*4+indM];
        if(aux_element==-1){
            int auxind;
            for(int i=0;i<4;i++){
                if(indM!=i && t[i]==t1){
                    auxind=i;
                }
            }
            indM=auxind;
        }
    }
    
    
    previous_element=boundary[current_element];
    current_element=neighbours[boundary[current_element]*4+indM];
    if (current_element==-1){
        d_res[idx]=result;
        return;
    }
    
    float sumt;
    unsigned long c=0;
    bool noNeighbours=false;
    while(!noNeighbours && c<15000){
        c++;
        // get instersection and lengths.
        isIntersect=tetraLineIntersect(elements,vertices,source,det,(unsigned int)current_element,t,true,0.0f);
        while(!isIntersect){
            isIntersect=tetraLineIntersect(elements,vertices,source,det,(unsigned int)current_element,t,true,safeEpsilon);
            if (nnz(t)<=1){
                isIntersect=false;
                safeEpsilon*=10;
            }
        }
        safeEpsilon=0.00001f;
        t2=max4(t,&indM);
        t1=min4nz(t);
//         mexPrintf("%u %.16f %.16f\n",(unsigned int)current_element,t2,t1);
//         mexPrintf("%.16f \n",(t2-t1));
        if (fabsf(t2-t1)<0.00000001){
            t2=t1;
            t[indM]=t1;
//             mexPrintf("hello! ");
        }
        sumt=0;
        for(int i=0;i<4;i++){
            sumt+=t[i];
        }
        
        if (sumt!=0.0){
            
            p2.x=direction.x* (t2);  p2.y=direction.y* (t2); p2.z=direction.z* (t2);
            p1.x=direction.x* (t1);  p1.y=direction.y* (t1); p1.z=direction.z* (t1);
            length=sqrt((p2.x-p1.x)*(p2.x-p1.x)+(p2.y-p1.y)*(p2.y-p1.y)+(p2.z-p1.z)*(p2.z-p1.z));
            // if (t1==t2); skip following line? timetest
            result+=d_image[current_element]*length;
            if(t1==t2){
                
                aux_element=neighbours[current_element*4+indM];
                if(aux_element==previous_element){
                    int auxind;
                    for(int i=0;i<4;i++){
                        if(indM!=i && t[i]==t1){
                            auxind=i;
//                            mexPrintf("hello! ");
                        }
                    }
                    indM=auxind;
                }
            }
            previous_element=current_element;
            current_element=neighbours[current_element*4+indM];
//             mexPrintf("%ld\n",current_element);
            if (current_element==-1){
                d_res[idx]=result;
                return;
            }
            continue;
        }
        noNeighbours=true;
    }//endwhile
    d_res[idx]=-1.0;
    return;
}
/*********************************************************************
 *********************** Main fucntion ************************
 ********************************************************************/
void graphForwardRay(float const * const  image,  Geometry geo,
                    const double * angles,const unsigned int nangles,
                    const double* nodes,const unsigned long nnodes,
                    const unsigned long* elements,const unsigned long nelements,
                    const long* neighbours,const unsigned long nneighbours,
                    const unsigned long* boundary,const unsigned long nboundary,
                    float ** result)
{
    float time;
    float timecopy, timekernel;
    cudaEvent_t start, stop;
    
     if (DEBUG_TIME){
        
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
        cudaEventRecord(start, 0);
    }
    
    size_t num_bytes_proj = geo.nDetecU*geo.nDetecV * sizeof(float);
    float * d_res;
    gpuErrchk(cudaMalloc((void **)&d_res,num_bytes_proj));
    
    size_t num_bytes_img  = nelements*sizeof(float);
    float* d_image;
    gpuErrchk(cudaMalloc((void **)&d_image,num_bytes_img));
    gpuErrchk(cudaMemcpy(d_image,image,num_bytes_img,cudaMemcpyHostToDevice));
    
    size_t num_bytes_nodes = nnodes*3*sizeof(double);
    double * d_nodes;
    gpuErrchk(cudaMalloc((void **)&d_nodes,num_bytes_nodes));
    gpuErrchk(cudaMemcpy(d_nodes,nodes,num_bytes_nodes,cudaMemcpyHostToDevice));
    
    size_t num_bytes_elements = nelements*4*sizeof(unsigned long);
    unsigned long * d_elements;
    gpuErrchk(cudaMalloc((void **)&d_elements,num_bytes_elements));
    gpuErrchk(cudaMemcpy(d_elements,elements,num_bytes_elements,cudaMemcpyHostToDevice));
    
    size_t num_bytes_neighbours = nneighbours*4*sizeof(long);
    long * d_neighbours;
    gpuErrchk(cudaMalloc((void **)&d_neighbours,num_bytes_neighbours));
    gpuErrchk(cudaMemcpy(d_neighbours,neighbours,num_bytes_neighbours,cudaMemcpyHostToDevice));
    
    size_t num_bytes_boundary = nboundary*sizeof(unsigned long);
    unsigned long * d_boundary;
    gpuErrchk(cudaMalloc((void **)&d_boundary,num_bytes_boundary));
    gpuErrchk(cudaMemcpy(d_boundary,boundary,num_bytes_boundary,cudaMemcpyHostToDevice));
    
    if (DEBUG_TIME){
        cudaEventRecord(stop, 0);
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&time, start, stop);
        
        mexPrintf("Time to memcpy:  %3.1f ms \n", time);
    }
    // Replace by a reduction
    vec3d nodemin, nodemax;
    nodemin.x=nodes[0];
    nodemin.y=nodes[1];
    nodemin.z=nodes[2];
    nodemax.x=nodes[0];
    nodemax.y=nodes[1];
    nodemax.z=nodes[2];
    
    for(unsigned long i=1;i<nnodes;i++){
        nodemin.x=(nodes[i*3+0]<nodemin.x)?nodes[i*3+0]:nodemin.x;
        nodemin.y=(nodes[i*3+1]<nodemin.y)?nodes[i*3+1]:nodemin.y;
        nodemin.z=(nodes[i*3+2]<nodemin.z)?nodes[i*3+2]:nodemin.z;
        nodemax.x=(nodes[i*3+0]>nodemax.x)?nodes[i*3+0]:nodemax.x;
        nodemax.y=(nodes[i*3+1]>nodemax.y)?nodes[i*3+1]:nodemax.y;
        nodemax.z=(nodes[i*3+2]>nodemax.z)?nodes[i*3+2]:nodemax.z;
    }
    
    // KERNEL TIME!
    int divU,divV;
    divU=8;
    divV=8;
    dim3 grid((geo.nDetecU+divU-1)/divU,(geo.nDetecV+divV-1)/divV,1);
    dim3 block(divU,divV,1);
    
    vec3d source, deltaU, deltaV, uvOrigin;
    
    for (unsigned int i=0;i<nangles;i++){
        geo.alpha=angles[i*3];
        geo.theta=angles[i*3+1];
        geo.psi  =angles[i*3+2];
        
        computeGeomtricParams(geo, &source,&deltaU, &deltaV,&uvOrigin,i);
        if (DEBUG_TIME){
            cudaEventCreate(&start);
            cudaEventCreate(&stop);
            cudaEventRecord(start, 0);
        }
        initXrays << <grid,block >> >(d_elements,d_nodes,d_boundary,nboundary, d_res, geo, source,deltaU, deltaV,uvOrigin,nodemin,nodemax);
//         testKernel<<<1,1>>>(cudaGraph,d_res);
        gpuErrchk(cudaPeekAtLastError());
        gpuErrchk(cudaDeviceSynchronize());
        
        graphProject<< <grid,block >> >(d_elements,d_nodes,d_boundary,d_neighbours,d_image,d_res, geo,source,deltaU,deltaV,uvOrigin);
        
        gpuErrchk(cudaPeekAtLastError());
        gpuErrchk(cudaDeviceSynchronize());
        
        if (DEBUG_TIME){
            cudaEventRecord(stop, 0);
            cudaEventSynchronize(stop);
            cudaEventElapsedTime(&timekernel, start, stop);
            
            
            cudaEventCreate(&start);
            cudaEventCreate(&stop);
            cudaEventRecord(start, 0);
        }
        
        gpuErrchk(cudaMemcpy(result[i], d_res, num_bytes_proj, cudaMemcpyDeviceToHost));
        
        if (DEBUG_TIME){
            cudaEventRecord(stop, 0);
            cudaEventSynchronize(stop);
            cudaEventElapsedTime(&timecopy, start, stop);
        }
    }
    
    
    if (DEBUG_TIME){
        mexPrintf("Time of Kenrel:  %3.1f ms \n", timekernel*nangles);
        mexPrintf("Time of memcpy to Host:  %3.1f ms \n", timecopy*nangles);
        
    }
    
    
    if (DEBUG_TIME){
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
        cudaEventRecord(start, 0);
    }
//     cudaGraphFree(&tempHostGraph,&tempHostElement,&tempHostNode);
    cudaFree(d_res);
    cudaFree(d_image);
    cudaFree(d_nodes);
    cudaFree(d_neighbours);
    cudaFree(d_elements);
    cudaFree(d_boundary);
    if (DEBUG_TIME){
        cudaEventRecord(stop, 0);
        cudaEventSynchronize(stop);
        cudaEventElapsedTime(&time, start, stop);
        
        mexPrintf("Time to free:  %3.1f ms \n", time);
    }
    return;
    
    
}


// this is fucking slow......... Copying an image of the same size in bytes is x1000 faster. (measured)
void cudaGraphMalloc(const Graph* inGraph, Graph **outGraph, Graph** outGraphHost, Element ** outElementHost, Node** outNodeHost){
    
    Graph* tempHostGraph;
    tempHostGraph = (Graph*)malloc(sizeof(Graph));
    
    //copy constants
    tempHostGraph->nNode = inGraph->nNode;
    tempHostGraph->nElement = inGraph->nElement;
    tempHostGraph->nBoundary = inGraph->nBoundary;
    
    
    
    // copy boundary
    gpuErrchk(cudaMalloc((void**)&(tempHostGraph->boundary), inGraph->nBoundary * sizeof(unsigned int)));
    gpuErrchk(cudaMemcpy(tempHostGraph->boundary, inGraph->boundary, inGraph->nBoundary * sizeof(unsigned int), cudaMemcpyHostToDevice));
    
    //Create nodes
    gpuErrchk(cudaMalloc((void**)&(tempHostGraph->node), tempHostGraph->nNode * sizeof(Node)));
    // Auxiliary host nodes
    Node* auxNodeHost = (Node *)malloc(tempHostGraph->nNode * sizeof(Node));
    for (int i = 0; i < tempHostGraph->nNode; i++)
    {
        auxNodeHost[i].nAdjacent = inGraph->node[i].nAdjacent;
        
        //Allocate device memory to position member of auxillary node
        gpuErrchk(cudaMalloc((void**)&(auxNodeHost[i].adjacent_element), inGraph->node[i].nAdjacent*sizeof(unsigned int)));
        gpuErrchk(cudaMemcpy(auxNodeHost[i].adjacent_element, inGraph->node[i].adjacent_element, inGraph->node[i].nAdjacent*sizeof(unsigned int), cudaMemcpyHostToDevice));
        
        //Allocate device memory to position member of auxillary node
        gpuErrchk(cudaMalloc((void**)&(auxNodeHost[i].position), 3 * sizeof(float)));
        gpuErrchk(cudaMemcpy(auxNodeHost[i].position, inGraph->node[i].position, 3 * sizeof(float), cudaMemcpyHostToDevice));
        
        //Copy auxillary host node to device
        gpuErrchk(cudaMemcpy(tempHostGraph->node + i, &auxNodeHost[i], sizeof(Node), cudaMemcpyHostToDevice));
    }
    
    
    //Create elements
    gpuErrchk(cudaMalloc((void**)&(tempHostGraph->element), tempHostGraph->nElement * sizeof(Element)));
    // Auxiliary host nodes
    Element* auxElementHost = (Element *)malloc(tempHostGraph->nElement * sizeof(Element));
    
    for (int i = 0; i < tempHostGraph->nElement; i++)
    {
        auxElementHost[i].nNeighbour = inGraph->element[i].nNeighbour;
        
        //Allocate device memory to position member of auxillary node
        gpuErrchk(cudaMalloc((void**)&(auxElementHost[i].neighbour), inGraph->element[i].nNeighbour*sizeof(unsigned int)));
        gpuErrchk(cudaMemcpy(auxElementHost[i].neighbour, inGraph->element[i].neighbour, inGraph->element[i].nNeighbour*sizeof(unsigned int), cudaMemcpyHostToDevice));
        
        //Allocate device memory to position member of auxillary node
        gpuErrchk(cudaMalloc((void**)&(auxElementHost[i].nodeID), 4 * sizeof(unsigned int)));
        gpuErrchk(cudaMemcpy(auxElementHost[i].nodeID, inGraph->element[i].nodeID, 4 * sizeof(unsigned int), cudaMemcpyHostToDevice));
        
        //Copy auxillary host node to device
        gpuErrchk(cudaMemcpy(tempHostGraph->element + i, &auxElementHost[i], sizeof(Element), cudaMemcpyHostToDevice));
    }
    // Copy the host auxiliary Graph to device.
    // Now we have no host access to this structure, so if you want to free its memory, we need to do it with the axiliary host variables.
    gpuErrchk(cudaMalloc((void**)outGraph, sizeof(Graph)));
    gpuErrchk(cudaMemcpy(*outGraph, tempHostGraph, sizeof(Graph), cudaMemcpyHostToDevice));
    
    *outGraphHost = tempHostGraph;
    *outNodeHost = auxNodeHost;
    *outElementHost=auxElementHost;
    return;
}

void cudaGraphFree(Graph** tempHostGraph, Element** tempHostElement, Node** tempHostNode){
    Graph * freeGraph = *tempHostGraph;
    Node * freeNode = *tempHostNode;
    Element * freeElement = *tempHostElement;
    
    for (int i = 0; i < freeGraph->nNode; i++){
        gpuErrchk(cudaFree(freeNode[i].adjacent_element));
        gpuErrchk(cudaFree(freeNode[i].position));
    }
    gpuErrchk(cudaFree(freeGraph->node));
    
    for (int i = 0; i < freeGraph->nElement; i++){
        gpuErrchk(cudaFree(freeElement[i].neighbour));
        gpuErrchk(cudaFree(freeElement[i].nodeID));
    }
    gpuErrchk(cudaFree(freeGraph->element));
    
    gpuErrchk(cudaFree(freeGraph->boundary));
}


// TODO: quite a lot of geometric transforms.
void computeGeomtricParams(const Geometry geo,vec3d * source, vec3d* deltaU, vec3d* deltaV, vec3d* originUV,unsigned int idxAngle){
    
    vec3d auxOriginUV;
    vec3d auxDeltaU;
    vec3d auxDeltaV;
    auxOriginUV.x=-(geo.DSD[idxAngle]-geo.DSO[idxAngle]);
    // top left
    auxOriginUV.y=-geo.sDetecU/2+/*half a pixel*/geo.dDetecU/2;
    auxOriginUV.z=geo.sDetecV/2-/*half a pixel*/geo.dDetecV/2;
    
    //Offset of the detector
    auxOriginUV.y=auxOriginUV.y+geo.offDetecU[idxAngle];
    auxOriginUV.z=auxOriginUV.z+geo.offDetecV[idxAngle];
    
    // Change in U
    auxDeltaU.x=auxOriginUV.x;
    auxDeltaU.y=auxOriginUV.y+geo.dDetecU;
    auxDeltaU.z=auxOriginUV.z;
    //Change in V
    auxDeltaV.x=auxOriginUV.x;
    auxDeltaV.y=auxOriginUV.y;
    auxDeltaV.z=auxOriginUV.z-geo.dDetecV;
    
    vec3d auxSource;
    auxSource.x=geo.DSO[idxAngle];
    auxSource.y=0;
    auxSource.z=0;
    
    // rotate around axis.
    eulerZYZ(geo,&auxOriginUV);
    eulerZYZ(geo,&auxDeltaU);
    eulerZYZ(geo,&auxDeltaV);
    eulerZYZ(geo,&auxSource);
    
    
    // Offset image (instead of offseting image, -offset everything else)
    auxOriginUV.x  =auxOriginUV.x-geo.offOrigX[idxAngle];     auxOriginUV.y  =auxOriginUV.y-geo.offOrigY[idxAngle];     auxOriginUV.z  =auxOriginUV.z-geo.offOrigZ[idxAngle];
    auxDeltaU.x=auxDeltaU.x-geo.offOrigX[idxAngle];           auxDeltaU.y=auxDeltaU.y-geo.offOrigY[idxAngle];           auxDeltaU.z=auxDeltaU.z-geo.offOrigZ[idxAngle];
    auxDeltaV.x=auxDeltaV.x-geo.offOrigX[idxAngle];           auxDeltaV.y=auxDeltaV.y-geo.offOrigY[idxAngle];           auxDeltaV.z=auxDeltaV.z-geo.offOrigZ[idxAngle];
    auxSource.x=auxSource.x-geo.offOrigX[idxAngle];           auxSource.y=auxSource.y-geo.offOrigY[idxAngle];           auxSource.z=auxSource.z-geo.offOrigZ[idxAngle];
    
    auxDeltaU.x=auxDeltaU.x-auxOriginUV.x;  auxDeltaU.y=auxDeltaU.y-auxOriginUV.y; auxDeltaU.z=auxDeltaU.z-auxOriginUV.z;
    auxDeltaV.x=auxDeltaV.x-auxOriginUV.x;  auxDeltaV.y=auxDeltaV.y-auxOriginUV.y; auxDeltaV.z=auxDeltaV.z-auxOriginUV.z;
    
    *originUV=auxOriginUV;
    *deltaU=auxDeltaU;
    *deltaV=auxDeltaV;
    *source=auxSource;
    
    return;
}

void eulerZYZ(Geometry geo,  vec3d* point){
    vec3d auxPoint;
    auxPoint.x=point->x;
    auxPoint.y=point->y;
    auxPoint.z=point->z;
    
    point->x=(+cos(geo.alpha)*cos(geo.theta)*cos(geo.psi)-sin(geo.alpha)*sin(geo.psi))*auxPoint.x+
            (-cos(geo.alpha)*cos(geo.theta)*sin(geo.psi)-sin(geo.alpha)*cos(geo.psi))*auxPoint.y+
            cos(geo.alpha)*sin(geo.theta)*auxPoint.z;
    
    point->y=(+sin(geo.alpha)*cos(geo.theta)*cos(geo.psi)+cos(geo.alpha)*sin(geo.psi))*auxPoint.x+
            (-sin(geo.alpha)*cos(geo.theta)*sin(geo.psi)+cos(geo.alpha)*cos(geo.psi))*auxPoint.y+
            sin(geo.alpha)*sin(geo.theta)*auxPoint.z;
    
    point->z=-sin(geo.theta)*cos(geo.psi)*auxPoint.x+
            sin(geo.theta)*sin(geo.psi)*auxPoint.y+
            cos(geo.theta)*auxPoint.z;
    
    
    
    
}
