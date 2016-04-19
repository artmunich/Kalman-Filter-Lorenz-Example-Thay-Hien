function out=AEnKF(dynfun,M,data,time,x0,R,V,P0,N,q,alpha,beta)
%
% AEnKF:  Adaptive Ensemble Kalman Filter
%
%      This implements the adaptive ensemble kalman filter using the method from
%      Rasteter et al (2010). This implementation uses linear observations given by
%      the observation matrix operator, M.  This EnKF code does 
%      estimation of the states and requires joint estimation to get
%      parameters 
%
%      INPUTS:
%           dynfun: rhs of ODE system (model) including the parameters (column vector)
%           M: operator matrix for observations
%           data: data points used for filter (column vector)
%           time: time period observations occur over
%           x0: initial condition for system
%           R:  Observation noise covariance, constant
%           V:  Process noise covariance
%           P0: initial state filter covariance
%		    q: parameter values
%           alpha:
%           beta:
%       OUTPUTS:
%           out.xfilter: state filter output 
%           out.P: State covariance matrices for each time
%           out.time: time scale
%           out.data: original data used for filter
%           out.tsd: +/- 3 std. deviations of state filter
%           out.ensemble: ensemble of particles at each time step
%
%
%

if ischar(dynfun)==1; dynfun=str2func(dynfun); end
if ischar(M)==1; M=str2func(M); end

%initialization 
L = length(data);   % number of time iterations
dt = time(2)-time(1);   % time step size
n = numel(x0);      % n, Dimension of state
Ap = zeros(n,N);

% initial ensembles, A, model, D, data
A = repmat(x0,1,N) + sqrt(P0)*randn(n,N);
            
%initialize filter 
xfilter=zeros(n,L);
P=cell(n,n,L);
tsd=zeros(L,n);

%initial conditions
xfilter(:,1) = x0;
P{1} = P0;
tsd(1,:) = (sqrt(diag(P{1}))*3)';
ensemble(:,:,1) = A;

%main filter loop
for k=2:L
    % Prediction Step: 
    % push each 'particle' of the ensemble through the model
    options = odeset('RelTol',1e-5,'AbsTol',1e-5);
    for j=1:N
        [tless, Aless] = ode15s(dynfun,[time(k-1) time(k)],A(:,j),options,q);
        Apstar(:,j) = Aless(end,:);
        %Ap(:,j) = rk4(dynfun,dt,time(k-1),A(:,j),q);
    end
    Ap = Apstar + real(sqrtm(V))*randn(n,N);
    
    % Analysis Step:
    % update the estimate of the state given the obervation
    % ie, calculate posterior through likelihood function
    
    %calculate ensemble perturbation matrix (51)
    I = 1/N*ones(N,N);
    Abar = Ap*I;
    Aprime = Ap-Abar;
    Abarstar = Apstar*I;
    d_istar = Apstar-Abarstar;
    
    %calculate estimate covariance, P_t (Table 1)
    %and
    %calculate uncorrupted estimate covariance P_tstar (table 2)
    P_t = (1/(N-1))*Aprime*Aprime';
    P_tstar = (1/(N-1))*d_istar*d_istar';
    
    %calculate Gamma_t for error distribution matrix, (table 2)
    % - distributes uncertainty in observed variables onto unobserved
    % variables -
    Gamma_t = ((1-beta)*inv(M*P_t*M')*(M*P_t*(eye(length(M))-M'*M)) + beta*M)';
    
    %calculate measurement matrix (54)
    D = repmat(data(k,:)',1,N);
    
    %calculate measurement perturbation matrix (55)
    E = sqrt(R)*randn(length(data(k,:)'),N);
    
    %calculate measurement error covariance matrix, C_ee (56)
    C_ee = (1/(N-1))*E*E';
    
    %calculate distributed error matrix for process noise
    Y_t = D - M*Ap+E;
    S_t = (1/(N-1))*Y_t*Y_t';
    Qhat_t = Gamma_t*(S_t - M*P_tstar*M' - R)*Gamma_t';
    V = alpha*V + (1-alpha)*Qhat_t;
    %V(V<0)=0;
    
    % calculate matrix holding measurements of ensemble perturbations
    % and other matrices required for update equation
    % (58,60,61,63)
    Dprime = D-M*A;
    S = M*Aprime;
    C = S*S' + (N-1)*C_ee;
    X = eye(N) + S'*(C\Dprime);
    
    %Update equation, A^a (62)
    A = Ap*X;
 
    %find mean and covariance of updated ensemble for filter
    meanA = mean(A,2);
    covA = (A-meanA(:,ones(1,N)))*(A-meanA(:,ones(1,N)))'/(N-1);
    
    %store solutions
    xfilter(:,k) = meanA;
    P{k} = covA;
    tsd(k,:) = (sqrt(diag(covA))*3)';
    ensemble(:,:,k) = A;
end

out.xfilter=xfilter';
out.P=P;
out.time=time;
out.data=data;
out.tsd=tsd;
out.ensemble = ensemble;

function dx=rk4(rhs,h,t,x,q)

% fourth order explicit rk integrator

k1=feval(rhs,t,x,q);
k2=feval(rhs,t+h/2,x+h/2*k1,q);
k3=feval(rhs,t+h/2,x+h/2*k2,q);
k4=feval(rhs,t+h,x+h*k3,q);

dx=x+(h/6)*(k1+2*k2+2*k3+k4);