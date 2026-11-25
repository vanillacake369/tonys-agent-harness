package core

import "io"

// Application은 CLI 조립 경계에 노출되는 상태 없는 유스케이스 파사드다.
type Application struct{}

func NewApplication() Application { return Application{} }

func (Application) ReadStatus() (StatusReport, error)        { return ReadStatus() }
func (Application) Init(source string) error                 { return Init(source) }
func (Application) Edit(target string) error                 { return Edit(target) }
func (Application) Reconcile(request ReconcileRequest) error { return Reconcile(request) }
func (Application) Lock() error                              { return Lock() }
func (Application) Purge() error                             { return Purge() }

/*
Application은 workspace 상태를 직접 보유하지 않고 기존 잠금·검증 경계에 위임한다.
*/
func (Application) Unlock(mode string) error                            { return Unlock(mode) }
func (Application) Graph(request GraphRequest, output io.Writer) error  { return Graph(request, output) }
func (Application) Connect(name string) error                           { return Connect(name) }
func (Application) Disconnect(name string) error                        { return Disconnect(name) }
func (Application) ReadProviders(name string) ([]ProviderStatus, error) { return ReadProviders(name) }
func (Application) ProviderNames() ([]string, error)                    { return ProviderNames() }
func (Application) UpdateSource(name, revision string) error            { return UpdateSource(name, revision) }
func (Application) ReadSources() ([]SourceStatus, error)                { return ReadSources() }
func (Application) PruneSourceCache(plan bool) (SourceCachePruneResult, error) {
	return PruneSourceCache(plan)
}
