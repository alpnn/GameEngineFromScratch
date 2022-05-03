#pragma once
#include "XcbApplication.hpp"
#include "glad/glad_glx.h"

namespace My {
class OpenGLApplication : public XcbApplication {
   public:
    using XcbApplication::XcbApplication;

    int Initialize() override;
    void Finalize() override;
    void Tick() override;

   protected:
    void CreateMainWindow() override;

   private:
    Display *m_pDisplay;
    int m_nScreen;
    GLXContext m_Context;
    GLXDrawable m_Drawable;
    GLXFBConfig fb_config;
    XVisualInfo *vi;
};
}  // namespace My
